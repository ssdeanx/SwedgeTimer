# Secret-API matrix — SwedgeTimer on WoW Forever (`origin/forever`)

Desk: `desks/forever-audit` (read-only; second task 2026-11-06). Client: WoW Forever /
Camelot 1.60.1, Interface 16001, `WOW_PROJECT_CAMELOT = 18`, Mainline-code
(`st.is_mainline == true`). Client claims are cited `origin/forever:path:line`; addon
claims are cited `file:line` **in the current tree** (the 2026-11-06 fix desks landed
`compat.lua`, `power_bar.lua`, `main.lua`, `bars.lua`, `hunter_ui.lua`,
`weave_range.lua`, `swing_source.lua`, `classes/hunter.lua`, `diag.lua`, `utils.lua` —
this report audits that settled state, not the pre-fix tree).

Priors not re-derived: `bench/powerbar_secret_2026-11-06.md` (power pass-through, landed),
`bench/forever_display_audit_2026-11-06.md` §10 (the `/st diag` probes),
`bench/display_fix_2026-11-06.md` (A/B fixes). The operator's runtime observation is the
premise that secret restrictions are active in ordinary Forever play (power read
restricted); §9 lists the exact in-client evidence that closes each open item.

Version fields are in flight (working tree reads 2.2.0 uncommitted; the
`desks/release-version` journal records operator-approved 2.1.8). This report makes no
version claim.

---

## 0. How to read this

- **§2–§5** are the matrix: every client API the addon calls that carries a
  `SecretWhen*` / `SecretArguments` annotation, what compat does with a secret value
  today, its consumers, and the verdict.
- **§6** is the pass-through sink matrix: which widgets can legally receive a secret
  from *tainted* addon code (the only way to display a secret at all).
- **§7** lists direct (non-compat) calls: the compat-rule violations and their risk.
- **§8** ranks the findings; **§9** is the UNVERIFIED table with the exact in-client
  probe that closes each row; **§10** separates "can be passed through" from
  "inherently undecidable".
- Verdict vocabulary: **DEGRADES-CORRECT** (unknown is honest and the consumer handles
  it), **UNKNOWN-HIDES** (feature disappears, no wrong claim), **READY-ON-UNKNOWN**
  (dangerous: a restricted read renders as "ready/0"), **TRUNCATION** (a secret row
  hides later readable rows), **THROW-RISK** (secret reaches comparison/arithmetic/
  concat/table key), **PASS-THROUGH** (secret rendered through a sanctioned sink).

---

## 1. Coverage and method

- Enumerated the compat surface (`compat.lua`, 61 named entries) and scanned every
  `.lua` in the addon for **bare global** calls of the secret-capable names (excluding
  `compat.lua`, `tests/`, `docs/`, `Libs/`), with alias awareness for the three files
  that rebind locals (`LibGlobalCooldown.lua:21-22,53-56`, `hud.lua:139`,
  `classes/druid.lua:331`).
- For every API: read its `origin/forever` generated API doc and quoted the predicate
  (`SecretWhen*`) or the argument rule (`SecretArguments`), plus the aspect
  (`SecretArgumentsAddAspect` / `SecretReturnsForAspect`).
- For every sink: same, plus Blizzard's own callsite where one proves the pattern.
- No unresolvable gap was guessed: §9 marks client-only facts UNVERIFIED and names the
  `/run` probe or the `/st diag` line that closes them (`diag.lua:754-789` already
  prints `secrets api=yes restrictions= cd= aura= power= stats= cast=`).

**APIs the addon does NOT call** (so they carry no finding, despite being secret-capable):
`UnitPowerPercent`, `UnitPowerMissing`, `UnitHealthPercent` (does not exist),
`GetSpellCharges`, `C_Spell.GetSpellCharges`, `UnitStat`, `UnitAttackPower`,
`UnitRangedAttackPower`, `UnitThreatSituation`, `GetActiveLossOfControlData`,
`UnitIsCharmed`, `UnitIsPossessed`, `UnitInRange`, `UnitIsConnected`,
`UnitIsDeadOrGhost`, `UnitLevel`, `UnitName` (outside the classic-gated enemy bar),
`UnitHealthPercent`. Verified by a repo-wide symbol count of 0 each (§7).

---

## 2. Matrix A — unit state, identity, resources, stats

| API | `origin/forever` annotation | Compat today (line) | Consumers | Loss / wrong behaviour | Safe sink / predicate | Minimal fix | Severity |
|---|---|---|---|---|---|---|---|
| `UnitPower` | `SecretWhenUnitPowerRestricted` — `UnitDocumentation.lua:2732-2747` (decl `:2734`); per power type unless flagged `NeverSecret` (`SecretPredicatesDocumentation.lua:150-153`) | `api.UnitPower` → **nil on secret** (`:600-611`); additive `api.GetPlayerPower` → **raw + flag** (`:641-651`) | 20 sites: rogue `:757,977,981`; druid `:508,546,1515,1644,1681,2513,2524,2531,2538`; warrior `:1185,2270,3424,4048`; paladin `:2506-2508`; hunter `:1878`; shaman `:3298`; power_bar via `GetPlayerPower` | Arithmetic consumers correctly read unknown (nil) and hold. **One wrong guess:** `classes/paladin.lua:2504-2513 get_guide_mana_pct` returns **0** on unknown → `inputs.mana_pct = 0` (`:3538`) → low-mana branches fire (`:3586-3596`, `:3998`). Power bar is **PASS-THROUGH** (below) | StatusBar `SetValue` (secret-capable); nil is the right value everywhere else | Paladin helper returns `nil` on unknown and the threshold branches gate on it (`if mana_pct and mana_pct > X`); keep `api.UnitPower` nil contract (pinned by `tests/secret_guard_state.lua:661-690`) | MED (paladin guess); else DEGRADES-CORRECT |
| `UnitPowerMax` | `SecretWhenUnitPowerMaxRestricted` — `:2801-2824` (decl `:2803`) | nil on secret (`:613-624`); `GetPlayerPower` raw (`:641-651`) | same 20 sites (paired with UnitPower) | Same as above; power bar PASS-THROUGH | StatusBar `SetMinMaxValues` | none beyond the paladin fix | DEGRADES-CORRECT |
| `UnitPowerType` | **No** `SecretWhen*` (`:2859-2878`, `MayReturnNothing` only) | nil only defensively (`:663-678`) | power_bar `:470-480`; druid `:2129` | Power TYPE always readable → the bar keeps its colour and type on Forever | n/a | none | INFO |
| `UnitHealth` | `SecretReturns = true` (PvP-restricted token arg) — `:1526-1541` | **nil on secret** (`:688-700`) | rogue TTD `:813`; druid TTD `:2406,2948`; warrior `:2190,3417,4060,4569,5135`; paladin `:3273`; hunter `:3489`; `forever_guide:563-575` (via `api.UnitHealth`) | TTD/execute estimates disappear (guarded by `type()==number`) — honest unknown. `forever_guide` falls back to `api.UnitHealth` first, so the safe wrapper wins | StatusBar `SetValue` if a health bar ever needs it | none | DEGRADES-CORRECT |
| `UnitHealthMax` | `SecretWhenUnitHealthMaxRestricted` — `:1472-1487` | nil on secret (`:701-712`) | same TTD/execute sites + `hud` mana? (no) | same | StatusBar `SetMinMaxValues` | none | DEGRADES-CORRECT |
| `UnitGUID` | `SecretWhenUnitIdentityRestricted` — `:1241-1256` | `api.UnitGUID` → nil on secret (`:1734-1745`) | `api.*`: rogue `:797`, druid uses a **raw local** (`:331`), hunter uses **raw globals** (`:1375,1582,1589`); `main.lua:577,1176,1177`; `classes/paladin.lua:996`; `hud.lua:139,363`; `enemy_swing.lua:310` | **THROW-RISK:** raw target GUIDs are compared (`classes/hunter.lua:1375`), stored then compared (`classes/druid.lua:2390,2397`), or read into a CLEU filter that never runs on Forever (`main.lua:1177`, gated off by `compat.lua:1554`). `type()=="string"` does **not** catch a secret (compat's own note `:163-171`) | none (identity is not renderable as a number); for a **stable target token**, a secret GUID may be compared only if both sides come from the same API — still not allowed to branch | Route every GUID through `api.UnitGUID` (nil on secret): hunter `:1375/1582/1589`, druid `:331`, hud `:139`, main target `:1177`; treat nil as "cannot identify target" | **HIGH** (hunter, druid) |
| `UnitName` | `SecretWhenUnitNameIdentityRestricted` — `:2489-2505` | no wrapper | `enemy_swing.lua:317` only (classic-gated by `:59-63`) | none on Forever | FontString `SetText` can carry a secret **string** (Text aspect) if ever needed | none | INFO |
| `UnitClass` | `SecretWhenUnitIdentityRestricted` — `:911-928` | no wrapper | `main.lua:413`, `utils.lua:65`, `option_tables.lua:79,156`, `option_table_presets.lua:1114`, `LibGlobalCooldown.lua:195` — all `"player"` | `"player"` is player-controlled → **not secret** by the predicate; the calls are a compat-rule violation only | n/a | optional: `api.UnitClass` wrapper for rule cleanliness | LOW |
| `UnitCreatureType` | `SecretWhenUnitIdentityRestricted` — `:1030-1045` | no wrapper | `classes/paladin.lua:2520-2526` (guarded by a local `is_secret`, `:17`); **`forever_guide.lua:555` unguarded** | **THROW-RISK:** `ct == "Undead"` compares a secret → raises inside the Forever HUD provider (guarded by `st.guard.run` at `hud.lua:1419-1426`, so it degrades to a hidden slot after 25 throws) | none | add `local is_secret = issecretvalue or …` to `forever_guide.lua` and return "unknown" on secret; or add `api.UnitCreatureType` | **HIGH** (latent) |
| `UnitIsUnit` | `SecretWhenUnitComparisonRestricted` — `:2410-2427`; **compound tokens are always secret on an addon-restricted map** (`SecretPredicatesDocumentation.lua:120-124`) | no wrapper | `classes/hunter.lua:1624` `UnitIsUnit("targettarget","player")` (option-gated ToT warning) | **THROW-RISK:** `yours == true or yours == 1` on a secret; `yours == nil` does not catch it | none | guard with `issecretvalue` → treat as unknown (return nil) | **HIGH** (latent; option default off) |
| `UnitAttackSpeed` | `SecretWhenUnitStatsRestricted` — `:682-697` | nil on any secret (`:1114-1127`) | `main.lua check_weapons` (fixed: only a readable number moves `has_weapon`), `swing_source.lua` (pcall + secret keep) | Honest unknown; the ranged/offhand bar no longer disables on a restricted read (fixed 2026-11-06) | `SetAlphaFromBoolean` if a weapon-state indicator is ever added | none | DEGRADES-CORRECT (fixed) |
| `UnitRangedDamage` | `SecretWhenUnitStatsRestricted` — `:2962-2981` | nil on secret (`:1130-1139`) | `check_weapons` (fixed), `swing_source` reset paths, `hunter_window`/`hunter_guide` inputs | honest unknown | n/a | none | DEGRADES-CORRECT |
| `GetUnitSpeed` | `SecretWhenUnitStatsRestricted` — `:335-352` | nil on secret/non-finite (`:1321-1340`) | `classes/hunter.lua:2569,2573` (weave prog) | nil player speed + `IsPlayerMoving()` fallback (`:2570-2571`); nil target speed → target_moving unknown → the prog holds | n/a | none | DEGRADES-CORRECT |
| `UnitSpellHaste` | `SecretWhenUnitStatsRestricted` — `:3132-3149` | nil on secret (`:1014-1024`) | `classes/shaman.lua:762-766` | Weave haste unknown → breakpoint marker/cast model hidden (UNKNOWN-HIDES) | n/a | none (honest) | MED (feature disappears in restricted combat) |
| `GetCombatRating` / `GetCombatRatingBonus` | `SecretWhenUnitStatsRestricted` — `PlayerScriptDocumentation.lua:303-318` / `:319-334` | **raw pass-through, no secret check** (`:1359-1372`) | `LibGlobalCooldown.lua:21-22` → its own guards (`:34-48`) | Latent: the wrapper hands a secret number to any future caller; LGC is safe today | n/a | guard both wrappers exactly like `api.GetUnitSpeed` (nil on `is_secret`) | MED (latent) |
| `UnitInRange`, `UnitIsDeadOrGhost`, `UnitExists`, `UnitCanAttack`, `UnitIsPlayer`, `UnitAffectingCombat`, `UnitIsEnemy`, `UnitIsConnected`, `UnitLevel` | **no `SecretWhen*`** (only `SecretArguments`) — e.g. `UnitExists :1192-1207`, `UnitCanAttack :763-780` | mostly no wrapper; direct calls are safe | many (target gates) | none — these never return secrets | n/a | none (rule-only; see §7) | INFO |

---

## 3. Matrix B — auras and casts

| API / event | `origin/forever` annotation | Compat today | Consumers | Loss / wrong behaviour | Safe sink | Minimal fix | Severity |
|---|---|---|---|---|---|---|---|
| `UnitAura` (classic global) | The **global is a deprecation shim** on classic game types: `Blizzard_Deprecated/Classic/Deprecated_1_15_8.lua:10-13` calls `C_UnitAuras.GetAuraDataByIndex` | Classic branch (`compat.lua:751-760`) has **no pcall and no `C_Secrets` precheck**; only the whole-entry field check. `C_UnitAuras.GetAuraDataByIndex` raises on a restricted row (`RequiresUnitAuraAccess`, FailureMode `Error`, `SecretPredicatesDocumentation.lua:48-50`) | any consumer when the shim exists | **THROW-RISK (latent):** if the shim is loaded on Forever, a restricted row raises through `api.UnitAura` instead of returning nil | n/a | mirror the C_UnitAuras branch: `aura_index_is_secret` precheck + `pcall(UnitAura, …)` on the classic branch too; no arity change | **HIGH (latent)** |
| `C_UnitAuras.GetAuraDataByIndex` | `SecretWhenUnitAuraRestricted` — `UnitAuraDocumentation.lua:208-226` | precheck `C_Secrets.ShouldUnitAuraIndexBeSecret` (`:738-750`) + `pcall` (`:763-783`) + whole-entry field guard (`:727-736`) | 20 scan sites (classes ×17, hud ×1, hunter_ui ×3) | Entry reads **absent** (nil), not "secret": correct contract — except the three hunter_ui loops (§4 row). Class scans use `if name ~= nil then` (continue) with explicit "no early break" comments (`warrior:2372`, `druid:1295`, `shaman:799,1862`, `hunter_ui` is the outlier) | n/a | fix hunter_ui's three loops (`:1277-1279`, `:1409-1411`, `:1762-1764`): replace `break` with continue; keep the 40-row cap | **TRUNCATION** in hunter_ui (MED); else DEGRADES-CORRECT |
| `C_UnitAuras.GetPlayerAuraBySpellID` | `SecretWhenUnitAuraRestricted` — `:397-414` | not used | — | — | n/a | none | INFO |
| `UNIT_AURA` event | `SecretWhenAurasRestricted = true` — `UnitAuraDocumentation.lua:645-655` | handler uses only `unit_id` (`main.lua:2058-2064`) and ignores `updateInfo` | class `on_aura_change` hooks | none (the payload is never read) | n/a | none | INFO |
| `UnitCastingInfo` / `UnitChannelInfo` | `SecretWhenUnitSpellCastRestricted` + `NeverSecret` on `castBarID` — `UnitDocumentation.lua:828-869` / `:870-905`; predicate: secret only when the unit is **not the player or pet** (`SecretPredicatesDocumentation.lua:115-119`) | nil on any secret field (`:945-970`) | shaman `:972-974`; class cast bars / shot sampler | For **player** casts the predicate is false → readable; a secret would mean a non-player unit, which the consumers do not query | n/a | none | DEGRADES-CORRECT |
| `UNIT_SPELLCAST_SUCCEEDED` / `_START` / `_FAILED…` | `SecretWhenUnitSpellCastRestricted` — `UnitDocumentation.lua:4845-4857` (`SUCCEEDED`), `:4819-4831` (`START`) | handlers return early on `unit_id ~= "player"` (`main.lua:2246-2271`, `:2380-2430`) | ranged shot receipt, class hooks | none: the payload is only used for player casts | n/a | none | INFO |
| `UNIT_POWER_UPDATE` / `UNIT_POWER_FREQUENT` | **no** `SecretWhen*` — `:4530-4539` / `:4552-4561` | handlers use `unit_id` only | power/rage tint refreshes | none | n/a | none | INFO |

---

## 4. Matrix C — cooldowns, charges, duration objects

| API | `origin/forever` annotation | Compat today | Consumers | Loss / wrong behaviour | Safe sink | Minimal fix | Severity |
|---|---|---|---|---|---|---|---|
| `GetSpellCooldown` / `C_Spell.GetSpellCooldown` | `SecretWhenCooldownsRestricted` — `SpellDocumentation.lua:309-326`; predicate covers combat/encounter/challenge/PvP (`SecretPredicatesDocumentation.lua:90-94`) | All four returns secret-checked before use (`:344-362`); `C_Spell` info table checked field-by-field (`:438-444`); readable `C_Spell.GetSpellCooldownDuration` object fallback (`:380-407`); fifth return `restricted` = "restricted and no readable source" (`:473-505`) | **28 real call sites** across 7 files (rogue 1, druid 2, shaman 5, warrior 2, paladin 12, hunter 3, forever_guide 3). **26 ignore the fifth return** (25 unpack 2 values; `classes/hunter.lua:1059` unpacks 3 where the third is `enabled`); only `forever_guide.lua:479,482` read it | **READY-ON-UNKNOWN:** a restricted read returns `0,0,0,0,true`, and a two-value consumer sees `duration == 0` → "ready". Examples that run on Forever: `classes/paladin.lua:1321,2467` (judgement/filler cue), `classes/shaman.lua:2110,2158,2187,2898` (weave cooldowns), `classes/hunter.lua:1059` (Auto Shot sync: stale cycle length), `classes/warrior.lua:3654`, `classes/druid.lua:2245`. The HUD slot path is covered (Forever uses `forever_guide.get_hud_state`, `hud.lua:225-236`, which sets `restricted` and `hud.paint` honors it `:1208-1216`) | CooldownFrame `SetCooldown` accepts a secret only from **untainted** code (below) — so the swipe cannot be painted from a restricted read; the honest render is the existing "unknown" state | One shared helper, e.g. `api.get_cooldown_remaining(token)` → `(remaining, restricted)`; when restricted return nil and set `inputs.inputs_unknown = true` (the contract `nextaction_ui.lua:638` and `forever_guide` already honor). Do **not** change the 4-value arity | **MED** (wrong "ready" advice on Forever) |
| `GetSpellCharges` / `C_Spell.GetSpellCharges` | `SecretWhenCooldownsRestricted` — `SpellDocumentation.lua:291-308` | **not wrapped, not called** (0 references) | — | — | — | none | INFO |
| `C_Spell.GetSpellCooldownDuration` + `LuaDurationObject` | Function `:327-344`; object methods `GetRemainingDuration :271-285`, `GetStartTime :303-317`, `GetTotalDuration :319-333`, `HasSecretValues :351-364` (`ReturnsNeverSecret = true`) | object read only when `HasSecretValues()` returns exactly `false`, all reads pcall'd, finite checks (`compat.lua:380-407`) | cooldown fallback | none — this is the one readable cooldown source while restricted | n/a | none | PASS (safe pattern) |
| `C_Secrets.*` predicates | `HasSecretRestrictions :93`, `ShouldAurasBeSecret :119`, `ShouldUnitAuraIndexBeSecret :220`, `ShouldUnitIdentityBeSecret :305`, `ShouldUnitPowerBeSecret :321`, `ShouldUnitPowerMaxBeSecret :338`, `ShouldUnitStatsBeSecret :388`, `GetPowerTypeSecrecy :29` | compat uses two (`:738-750`, `:911-930`); `/st diag` uses six (`diag.lua:754-789`) | aura precheck, observability, diag | none | n/a | none (optionally use `ShouldUnitPowerBeSecret` before the raw power paint; the flag already says it) | INFO |

---

## 5. Matrix D — items, totems, combat log

| API | `origin/forever` annotation | Compat today | Consumers | Loss / wrong behaviour | Safe sink | Minimal fix | Severity |
|---|---|---|---|---|---|---|---|
| `GetTotemInfo` | `SecretWhenTotemSlotSecret` — `TotemDocumentation.lua:59-80`; `MayReturnNothing` | any secret field → **nil** (`compat.lua:1581-1610`) | shaman `:1097,1174,1207,1242,3423,3681,4057` | **UNKNOWN-HIDES with a wrong flavour:** `nil` is documented as "absent", so `if not have_totem then` (`:1242-1245`, `:4057`) reads a restricted slot as **no totem** → the weave/Fire-totem cue can prompt a re-drop or assume "no totem" | `SetAlphaFromBoolean` on a totem indicator if one is added | additive: `api.GetTotemInfo` returns an 8th `restricted` boolean, or add `api.totems_may_be_secret()` (the `auras_may_be_secret` pattern `compat.lua:911-930`) and have the shaman cues treat unknown as hold | **MED** |
| `GetItemCooldown` / `C_Item.GetItemCooldown` | No `SecretWhen*`; `SecretArguments` only — `ItemDocumentation.lua:434-449`; the addon prefers `C_Item` (`compat.lua:1616-1631`) | pcall + secret guard → `(0,0,0)` (`:1691-1705`) | bag-item consumers (Thistle Tea probes) | none secret-wise | n/a | none | DEGRADES-CORRECT |
| `GetInventoryItemCooldown` | **Absent from the generated docs** (unannotated global; Blizzard's own FrameXML still calls it, e.g. `Blizzard_FrameXML/Mainline/EquipmentManager.lua`) | global read through `_G`; secret or absent → `(0,0,0)` (`:1425-1450`) | `hud.lua:334-346 trinket_has_on_use` → `use_enable == 0` → trinket is judged **not usable** and the slot hides (`:352-374`) | **UNKNOWN-HIDES + wrong flavour:** a restricted/absent read makes an on-use trinket vanish instead of showing unknown | `SetAlphaFromBoolean` / `SetDesaturated` if a restricted trinket state is rendered | additive `restricted` fifth return (or a probe) and keep the slot visible as unknown; verify the global exists on Forever (§9 V4) | **MED** |
| `GetInventoryItemID` / `GetInventoryItemTexture` | Same unannotated family | secret → nil (`:1398-1424`) | hud trinket identity; shaman shield probe | nil → unknown item → slot hidden (honest) | n/a | none | DEGRADES-CORRECT |
| `GetItemInfo` / `GetItemCount` / `GetWeaponEnchantInfo` | No `SecretWhen*` (`ItemDocumentation.lua:626-650`, `:451-466`, `:1141-1160`) | pcall + secret guards (`:1650-1725`) | trinket/poison/tea | none | n/a | none | DEGRADES-CORRECT |
| `CombatLogGetCurrentEventInfo` | classic-line only; absent on Forever | `st.cleu_supported = … and not st.is_mainline` (`:1554`); registration gated (`main.lua:765-767`) | paladin twist, warrior parry, hud procs | not reachable on Forever | n/a | none | INFO |

---

## 6. Pass-through / sink matrix (what may carry a secret from **tainted** addon Lua)

Legend: **YES** = secret argument accepted from tainted code (the aspect is attached);
**NO** = secret arguments only from untainted/secure code (`AllowedWhenUntainted`) or a
protected function; **YES-STRING** = a secret *string* is carried, numbers cannot be
formatted.

| Sink | `origin/forever` annotation | Secret from tainted? | What it can display | Verdict |
|---|---|---|---|---|
| `StatusBar:SetMinMaxValues` | `AllowedWhenTainted`, aspect `{BarValue}` — `SimpleStatusBarAPIDocumentation.lua:229-236` | **YES** | raw current/max power, health | **USABLE — implemented** (`power_bar.lua:623-632`, paint `:388-420`; raw reader `compat.lua:641-651`). Blizzard does the same: `Blizzard_UnitFrame/Mainline/UnitFrame.lua:948,950,962,970` |
| `StatusBar:SetValue` | same — `:354-361` | **YES** | raw value | **USABLE — implemented** |
| `StatusBar:SetStatusBarColor` / `SetStatusBarDesaturated` | `AllowedWhenTainted`, aspects `{VertexColor,Alpha}` / `{Desaturation}` — `:282-300` | **YES** | a secret colour/desaturation (e.g. health→colour) | USABLE (not needed yet) |
| `StatusBar:GetValue` / `GetMinMaxValues` | `SecretReturnsForAspect {BarValue}` — `:162-171`, `:38-46` | read-back may be **secret** | — | NEVER read back after a secret paint; the addon does not (`grep`: no `GetValue` in power_bar/hud) |
| `FontString:SetText` | `AllowedWhenTainted`, aspect `{Text}` — `SimpleFontStringAPIDocumentation.lua:664-673` | **YES-STRING** | a secret *string* (e.g. a secret unit name); numbers cannot be converted | USABLE for strings only |
| `FontString:SetTextToFit` | same — `:708-718` | **YES-STRING** | same | USABLE for strings |
| `FontString:SetFormattedText` | `AllowedWhenTainted`, `{Text}` — `:539-548`; **the documented signature takes ONE `cstring` argument — no format/varargs** | **NO for `("%d", secret)`** | — | **`SetFormattedText("%d", secret_number)` is NOT supported by the client signature**, and Lua-side `string.format("%d", secret)` raises (arithmetic/format on a secret). **UNVERIFIED at runtime**; recommendation: keep the current `"?"` fallback (`power_bar.lua:415`). Evidence to close: §9 V7 |
| `FontString:SetTextColor` | `AllowedWhenTainted`, `{VertexColor,Alpha}` — `:675-687` | **YES** | secret colour | USABLE |
| `ScriptRegion:SetAlpha` | `AllowedWhenTainted`, `{Alpha}` — `SimpleFrameAPIDocumentation.lua:1134-1143` | **YES** | a secret alpha number | USABLE |
| `ScriptRegion:SetAlphaFromBoolean` | `AllowedWhenTainted`, `{Alpha}` — `SimpleRegionAPIDocumentation.lua:134-145`; `SimpleFrameAPIDocumentation.lua:1145-1156` | **YES** (secret **bool**) | show/hide-style state from a secret bool | **USABLE — the sanctioned way to visualise a secret boolean**. Blizzard's own guidance: *"Tainted callers must apply showRoleIcon with SetAlphaFromBoolean; SetShown does not accept secret arguments from tainted execution"* — `Blizzard_UnitFrame/Shared/UnitFrameUtil.lua:487` |
| `ScriptRegion:SetVertexColor` | `AllowedWhenTainted`, `{VertexColor,Alpha}` — `SimpleRegionAPIDocumentation.lua:191-203` | **YES** | secret colour | USABLE |
| `Texture:SetColorTexture` | `AllowedWhenTainted` (forbidden-aspect check on self) — `SimpleTextureBaseAPIDocumentation.lua:403-415` | **YES** | secret colour | USABLE |
| `Texture:SetDesaturated` | `AllowedWhenTainted`, `{Desaturation}` — `:417-426` | **YES** (secret bool) | grey-out from a secret bool | USABLE |
| `Texture:SetTexCoord` | `AllowedWhenTainted`, `{TexCoords}` — `:580-592` | **YES** | a secret ratio (progress) | USABLE (a progress bar could be driven without arithmetic if a secret fraction existed; UnitPower gives absolute values only) |
| `Texture:SetTexture` | `AllowedWhenTainted` — `:604-620` | **YES** for a secret asset string/fileID | secret icon | USABLE (not needed) |
| `Frame:SetShown` | `AllowedWhenUntainted`, `IsProtectedFunction` — `SimpleFrameAPIDocumentation.lua:1484-1493` | **NO** | — | Use `SetAlphaFromBoolean` (see Blizzard note above) |
| `ScriptRegion:SetPoint` / `SetSize` / `SetWidth` / `SetHeight` / `SetScale` | `AllowedWhenUntainted` — `SimpleScriptRegionResizingAPIDocumentation.lua:135,163,175,124`; `SimpleRegionAPIDocumentation.lua:179-189` (`SetScale` is also `IsProtectedFunction`) | **NO** | — | Layout must stay on readable numbers (it does) |
| `GetPoint` / `GetLeft` / `GetTop` / `GetWidth` / `GetHeight` / `GetRect` / `GetSize` | `SecretWhenAnchoringSecret` — `SimpleScriptRegionResizingAPIDocumentation.lua:65`; `SimpleScriptRegionAPIDocumentation.lua:178,308,323,161,193,276` | returns **may be secret** when the frame's anchoring is secret | — | Addon-owned frames are safe (their `SetPoint` inputs are readable); do not anchor the bars to a Blizzard frame that could carry secret anchoring and then do math on its geometry |
| `GetFrameLevel` / `GetFrameStrata` / `GetScale` | `SecretReturnsForAspect` — `SimpleFrameAPIDocumentation.lua:421,435,621` | read-back may be secret | — | Same caution: the addon reads only its own frames (`hunter_ui.lua` layering, `power_bar.lua` layout) — safe |
| `CooldownFrame:SetCooldown` / `SetCooldownDuration` / `SetCooldownFromDurationObject` / `SetCooldownFromExpirationTime` / `SetCooldownUNIX` | `AllowedWhenUntainted`, `IsProtectedFunction`, aspect `{Cooldown}` — `FrameAPICooldownDocumentation.lua:281-293` (SetCooldown), `:295-306` (SetCooldownDuration), `:308-318` (FromDurationObject), `:320-332` (FromExpirationTime), `:334-346` (UNIX) | **NO** | — | **The HUD swipe cannot be driven from a restricted read**; the existing unknown state (`hud.lua:1208-1216`) is the correct answer |
| `CooldownFrame:GetCooldownTimes` / `GetCooldownDuration` | `SecretReturnsForAspect {Cooldown}` — `FrameAPICooldownDocumentation.lua:34-48,49-63` | read-back may be secret | — | never read back after a secret set (the addon does not) |
| `Hide` / `Show` | no arguments, always callable | **n/a** | — | The *decision* cannot be made from a secret (branching is forbidden); use `SetAlphaFromBoolean` instead |

**Verified sink outcome for this addon's features:** the power bar is the one feature that
already uses a legal pass-through (`StatusBar`); no other current feature has a
secret-only value that a sink could render without arithmetic (see §10).

---

## 7. Direct API calls outside compat (rule violations + risk)

Rule: `AGENTS.md` — "Never call a cross-client API directly elsewhere; go through
`st.api`." Scan: bare globals of the secret-capable names, alias-aware.

| Call site | Call | Verdict |
|---|---|---|
| `classes/hunter.lua:1375` | `UnitGUID("target") ~= self.hunter_tint_target` | **THROW-RISK — fix first**: raw secret identity compared every tick (`maintain_queue_tint`). Route through `api.UnitGUID` and treat nil as unknown |
| `classes/hunter.lua:1582,1589` | `self.hunter_tint_target = UnitGUID("target")` | **THROW-RISK — same fix** (raw secret stored; consumed at `:1375`) |
| `classes/hunter.lua:1624` | `UnitIsUnit("targettarget","player")` | **THROW-RISK**: compound token is always secret on a restricted map; guard with `issecretvalue` or route through a new `api.UnitIsUnit` tri-state |
| `classes/druid.lua:331,2390,2397` | `local unit_guid = UnitGUID`; `guid = unit_guid("target")`; `guid ~= self.druid_ttd_guid` | **THROW-RISK**: `type(guid) ~= "string"` cannot see a secret (`compat.lua:163-171`); use `api.UnitGUID` |
| `forever_guide.lua:555` | `UnitCreatureType("target")` then `ct == "Undead"` | **THROW-RISK** (HUD provider, guarded by `st.guard.run` so it ends as a hidden slot after 25 throws) |
| `main.lua:1177` | `UnitGUID("target")` in the CLEU filter | Latent only: the handler is unreachable on Forever (`st.cleu_supported` false, `compat.lua:1554`; registration `main.lua:765-767`); still a rule violation |
| `hud.lua:139,363` | `local unit_guid = rawget(_G,"UnitGUID")` used by `HUD.on_aura_applied` | Latent (CLEU-only path, dead on Forever); rule violation |
| `main.lua:577,1176`, `classes/paladin.lua:996` | `UnitGUID("player")` | No secret risk (player identity is player-controlled, `SecretPredicatesDocumentation.lua:130-134`); rule violation (use `api.UnitGUID`) |
| `main.lua:413`, `utils.lua:65`, `option_tables.lua:79,156`, `option_table_presets.lua:1114`, `LibGlobalCooldown.lua:195` | `UnitClass("player")` | No secret risk; rule violation only |
| `practice_ui.lua:405` | `GetSpellTexture(spell_id)` | No `SecretWhen*` on `GetSpellTexture` (`SpellDocumentation.lua:595-613`); rule violation only |
| `enemy_swing.lua:305,307,310,317,516` | `UnitExists/UnitCanAttack/UnitGUID/UnitName/UnitAffectingCombat` | Module is family-gated to the classic line (`enemy_swing.lua:59-63`; `read_target` comment `:300-303`) and never runs on Forever — not a secret risk |
| NOT violations | `LibGlobalCooldown.lua:122,158,237` (`GetSpellInfo`/`GetSpellCooldown`), `hud.lua:363` (`unit_guid`) | These are **local aliases** of `api.*` (`LibGlobalCooldown.lua:21-22,53-56`; `hud.lua:139` is the raw one, listed above) — no secret reaches them |
| Safe by predicate | all `UnitExists`/`UnitCanAttack` target gates (`main.lua:2513-2514`, `weave_range.lua:449,455`, class modules), `UnitAffectingCombat`, `UnitIsDeadOrGhost`, `UnitLevel` | No `SecretWhen*` on these APIs — never secret |

---

## 8. Ranked findings

| ID | Sev | Conf | Finding | Exact code |
|---|---|---|---|---|
| SEC-1 | **HIGH** | HIGH (code) / MED (trigger) | Hunter target identity read raw and **compared** every tint tick; a restricted GUID raises (or branches on a secret) inside the bar tick. | `classes/hunter.lua:1375,1582,1589`; doc `UnitDocumentation.lua:1241-1256`; compat safe wrapper `compat.lua:1734-1745` |
| SEC-2 | **HIGH** | HIGH (code) / MED (trigger) | `UnitIsUnit("targettarget","player")` uses a compound token → **always secret** on an addon-restricted map; unguarded comparison/return. | `classes/hunter.lua:1624`; predicate `SecretPredicatesDocumentation.lua:120-124`; doc `UnitDocumentation.lua:2410-2427` |
| SEC-3 | **HIGH** | HIGH (code) / UNVERIFIED (trigger) | Forever HUD provider compares `UnitCreatureType("target")` unguarded; a secret identity read throws (isolated by `st.guard.run`, so the Exorcism slot silently goes dark after 25 throws). | `forever_guide.lua:555`; doc `UnitDocumentation.lua:1030-1045`; guard site `hud.lua:1419-1426` |
| SEC-4 | **HIGH** | HIGH (code) / UNVERIFIED (client) | `api.UnitAura`'s **classic branch** has no `pcall`/`C_Secrets` precheck; the classic `UnitAura` is a deprecation shim over the raisable `C_UnitAuras.GetAuraDataByIndex`. If the shim is loaded on Forever, one restricted row raises through the wrapper. | `compat.lua:751-760`; shim `Blizzard_Deprecated/Classic/Deprecated_1_15_8.lua:10-13`; raise failure mode `SecretPredicatesDocumentation.lua:48-50`; guarded sibling `compat.lua:762-783` |
| SEC-5 | MED | HIGH | Druid TTD baselines a **raw** target GUID; `type()=="string"` cannot detect a secret, so the compare is the failure point. | `classes/druid.lua:327-331,2388-2397` |
| SEC-6 | MED | HIGH | 26 of 28 `api.GetSpellCooldown` consumers ignore the fifth (`restricted`) return → a restricted read is treated as **ready** in class-side cues/inputs on Forever. | `compat.lua:473-505` (contract); consumers e.g. `classes/paladin.lua:2461-2480`, `classes/shaman.lua:2110`, `classes/hunter.lua:1059`, `classes/warrior.lua:3654`, `classes/druid.lua:2245`; honorers `forever_guide.lua:477-507` |
| SEC-7 | MED | HIGH | Three hunter aura scans `break` on `not name`; a restricted row (returned as absent by compat) **truncates** the scan, hiding Rapid-Fire/Frenzy/Aspect state that is readable at later indexes. | `hunter_ui.lua:1273-1285` (break `:1277-1279`), `:1405-1415` (`:1409-1411`), `:1758-1772` (`:1762-1764`); contrast `classes/warrior.lua:2372`, `compat.lua:812-833` ("no early break") |
| SEC-8 | MED | HIGH | `GetTotemInfo` collapsing a secret slot to `nil` makes shaman callers read "no totem" (a wrong claim, not an unknown). | `compat.lua:1581-1610`; consumers `classes/shaman.lua:1242-1245,4057`; doc `TotemDocumentation.lua:59-80` |
| SEC-9 | MED | HIGH | `get_guide_mana_pct` returns **0** on an unknown power read → the paladin guide takes low-mana branches. | `classes/paladin.lua:2504-2513`, used `:3538,3586-3596,3998` |
| SEC-10 | MED | HIGH | Trinket on-use detection treats a restricted/absent inventory cooldown as "no on-use" → the trinket slot hides instead of showing unknown. | `hud.lua:334-346,352-374`; wrapper `compat.lua:1425-1450` |
| SEC-11 | MED | HIGH (latent) | `api.GetCombatRating`/`GetCombatRatingBonus` are **raw pass-throughs** with no secret guard; safe today only because `LibGlobalCooldown` guards its own reads. | `compat.lua:1359-1372`; guard `LibGlobalCooldown.lua:34-48`; doc `PlayerScriptDocumentation.lua:303-334` |
| SEC-12 | MED | HIGH | Shaman spell-haste read silently disappears under restricted stats → weave breakpoint marker/cast model hidden (honest, but a visible feature loss on Forever in combat). | `classes/shaman.lua:762-766`; `compat.lua:1014-1024`; doc `UnitDocumentation.lua:3132-3149` |
| SEC-13 | LOW | HIGH | `SetFormattedText("%d", secret_number)` is **not supported**: the Forever signature takes one `cstring`, and Lua formatting of a secret raises. Keep `"?"`. | Doc `SimpleFontStringAPIDocumentation.lua:539-548`; fallback `power_bar.lua:415` |
| SEC-14 | LOW | HIGH | Direct `UnitClass("player")`/`GetSpellTexture`/player-GUID calls violate the compat rule but cannot return secrets (player-controlled / no predicate). | `main.lua:413,577,1176`; `utils.lua:65`; `option_tables.lua:79,156`; `option_table_presets.lua:1114`; `LibGlobalCooldown.lua:195`; `practice_ui.lua:405` |
| SEC-15 | INFO | HIGH | Secret-capable APIs never called (no action): `GetSpellCharges`, `UnitStat`, `UnitAttackPower`, `UnitRangedAttackPower`, `UnitThreatSituation`, `GetActiveLossOfControlData`, `UnitIsCharmed/Possessed`, `UnitInRange`, `UnitPowerPercent`, `UnitPowerMissing`. | §1 list; 0 hits each |
| SEC-16 | INFO | HIGH | Latent rule violation in the dead CLEU path: `main.lua:1177` + `hud.lua:139` read `UnitGUID("target")` raw; harmless on Forever because `st.cleu_supported` is false and the event is not registered. | `compat.lua:1554`; `main.lua:765-767` |

---

## 9. UNVERIFIED items and what closes them

`/st diag` already prints the switches (`diag.lua:754-789`):
`secrets api=yes restrictions=<bool> cd=<bool> aura=<bool> power=<bool> stats=<bool> cast=<bool>`.
Run it on Forever in the failing moment; each row names the flag or `/run` probe.

| # | Unverified | Why it matters | Closing evidence |
|---|---|---|---|
| V1 | Whether restrictions are active **in ordinary PvE combat** on Forever (or only PvP/instances) | Every MED finding is contextual; a false `restrictions` makes them dormant | `/st diag` → `secrets … restrictions=`; plus `power=`, `stats=`, `cd=`, `aura=` at the same moment |
| V2 | Whether `UnitGUID("target")` actually returns a secret from tainted Lua on this client | SEC-1/SEC-5 trigger | `/run local g=UnitGUID("target") print(type(g), issecretvalue(g))` in combat with a mob target |
| V3 | Whether `UnitIsUnit("targettarget","player")` returns a secret on this client's restricted maps | SEC-2 trigger | `/run print(issecretvalue(UnitIsUnit("targettarget","player")))` with the ToT option on |
| V4 | Whether the global `UnitAura` (deprecation shim) exists on the Camelot game type | SEC-4 decides which compat branch is live | `/run print(type(UnitAura), type(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex))` |
| V5 | Whether `GetInventoryItemCooldown`/`GetInventoryItemID` exist as globals on Forever | SEC-10 (absent → trinket gap even without secrets) | `/run print(type(GetInventoryItemCooldown), type(GetInventoryItemID))` |
| V6 | Whether `UnitCreatureType("target")` is secret in normal play | SEC-3 trigger | `/run print(issecretvalue(UnitCreatureType("target")))` with a hostile target |
| V7 | Whether `SetFormattedText` accepts extra varargs at runtime on Forever (the doc signature says one arg) | SEC-13; if it accepted `%d` + secret the text could render | `/run local f=UIParent:CreateFontString(nil,"OVERLAY") print(pcall(f.SetFormattedText,f,"%d",UnitPower("player")))` in restricted combat (careful: a raise here is the answer) |
| V8 | Whether a restricted cooldown swipe is accepted by `CooldownFrame:SetCooldown` from tainted code (doc says no: `AllowedWhenUntainted`) | Would change the HUD unknown-state fix | `/run print(pcall(function() local c=CreateFrame("Cooldown",nil,UIParent); c:SetCooldown(GetTime(), GetSpellCooldown(75)) end))` — but note the arguments would already be secret before the call; do not rely on this as a fix path |

---

## 10. What can be passed through vs what is inherently undecidable

**Pass-through (legal today, or one small wrapper away):**
- Current/max resource values → `StatusBar:SetMinMaxValues`/`SetValue` (implemented for the
  power bar; the only secret-capable feature with a real sink).
- A secret **boolean** claim → `SetAlphaFromBoolean` (sanctioned; Blizzard says so at
  `UnitFrameUtil.lua:487`) — e.g. "in range", "usable", "buff up" if a future client ever
  returns them as secrets.
- A secret **colour / desaturation / texcoord / texture** → `SetVertexColor`,
  `SetStatusBarColor`, `SetColorTexture`, `SetDesaturated`, `SetTexCoord`, `SetTexture`.
- A secret **string** → `FontString:SetText` / `SetTextToFit` (Text aspect). This is the
  only way a secret name/word can be shown.

**Inherently undecidable for a tainted addon (must render "unknown"):**
- Any **number shown as text**: remaining seconds, percentages, damage, TTD, stacks — Lua
  cannot format or concatenate a secret, and `SetFormattedText` takes no varargs.
- Any **arithmetic**: fractions (`value/max`), comparisons (`>=`, `> 0`), sums, EMA/velocity,
  cooldown `start + duration - now`.
- Any **branching**: `if secret_bool then`, `x == nil`-style tests do not see a secret
  (`type()` still reports the underlying type — `compat.lua:163-171`).
- Any **table key / identity**: secret GUIDs/names cannot key a table, be
  concatenated into a string, or be compared for a stable identity.
- **Cooldown swipes from restricted reads**: `CooldownFrame:SetCooldown*` is
  untainted-only, so the honest render is the HUD's unknown state.
- **Layout driven by a secret**: `SetPoint`/`SetSize`/`SetScale` are untainted-only.

The design consequence already implemented: the power bar paints the raw bar and shows
`"?"` for the text; the HUD greys a restricted slot and draws no swipe; everything else
returns nil/unknown and hides rather than guessing. The remaining gaps are the unsafe
**branches** (SEC-1/2/3/SEC-5), the **truncating** scans (SEC-7), and the **guesses**
(SEC-6/8/9/10).

---

## 11. Minimal fix order (for the dispatch desk)

1. SEC-1 + SEC-5 (one-line-class fixes): replace `UnitGUID(` with `api.UnitGUID(` in
   `classes/hunter.lua:1375,1582,1589`, `classes/druid.lua:331` (and its use at `:2390`),
   `hud.lua:139`, `main.lua:1177`. Nil already means "cannot identify" in every consumer.
2. SEC-2: add the local `is_secret` guard in `classes/hunter.lua` (the pattern is in
   `classes/paladin.lua:17`) and return nil when `UnitIsUnit` answers secret.
3. SEC-3: same guard in `forever_guide.lua` for the `UnitCreatureType` read.
4. SEC-4: mirror the C_UnitAuras precheck+pcall into the classic `UnitAura` branch
   (`compat.lua:751-760`) — no arity change, no classic behaviour change when nothing is
   secret.
5. SEC-7: drop the three `break`s in `hunter_ui.lua` (continue, cap 40 — the unchanged
   pattern from `compat.lua:812-860`).
6. SEC-6: one shared restricted-aware remaining-time helper + `inputs_unknown` threading
   (the `nextaction_ui.lua:638` contract already exists); fix the guides' `is_off_cooldown`
   to receive an explicit unknown rather than nil-as-ready.
7. SEC-8/9/10 + SEC-11: additive flags/probes (`GetTotemInfo` eighth return,
   `GetInventoryItemCooldown` fifth, a guarded `GetCombatRating`), and the paladin
   `mana_pct = nil` change.
8. SEC-12/13/14/15/16: notes only; no code required unless a feature needs them.

Every fix keeps the pinned contracts (`tests/secret_guard_state.lua` wrappers;
`tests/forever_secret_compat_state.lua` raw reader; `tests/power_bar_state.lua`).

---

## 12. Read-only attestation

- No product code, tests, TOCs, README/CHANGELOG, `Libs/`, `docs/` or git history was
  modified. New files only: this report, `desks/forever-audit/journal.md` (appended) and
  a done signal in `desks/forever-audit/.signals/`.
- The tree is in flux from parallel fix desks (10 product files modified, version fields
  in flight); every addon line number above was read in the current working tree at
  2026-11-06T~21:2xZ. Re-read a line before editing it.
- Note: `desks/secret-consumers-audit/` exists but was empty at write time; if another
  desk is auditing the same consumers, reconcile before both file fixes.
