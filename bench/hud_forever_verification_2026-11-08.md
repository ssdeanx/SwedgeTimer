# Independent verification — Forever HUD cooldown/GCD + Forever aura row (2026-11-08)

- **Team / task:** `swedge-forever-hud` / **t5**, attempt 1
  (`c9c05608-3a85-49c7-b181-b959bdf40757`). Verifier lane.
- **Mode:** read-only on product / tests / TOC / config / options / docs. **No git command
  was run in this repository, no product file was written, no version changed.** The only
  writes are this report, `desks/aura-hud-verify/**`, and the `/tmp` copies used for the
  mutation proofs (the `/tmp` copies are per-call throwaways in this environment).
- **Brief executed:** `bench/briefs/brief_hud_forever_verify_2026-11-08.md`.
- **Lanes verified:** t3 (`bench/hud_forever_cooldown_2026-11-08.md`: `hud.lua`,
  `compat.lua`, `LibGlobalCooldown.lua`, `tests/hud_state.lua`,
  `tests/forever_secret_compat_state.lua`) and t4 (`bench/aura_row_2026-11-08.md`:
  `aura_icons.lua`, `tests/aura_icons_state.lua`, `SwedgeTimer.toc`, `main.lua`,
  `config_presets.lua`, `option_tables.lua`, `tests/run.sh`, `tests/toc_check.lua`).
- **Contract inputs:** `bench/forever_hud_api_2026-11-08.md` (T1),
  `bench/aura_row_reference_2026-11-08.md` (T2), both implementation reports,
  `AGENTS.md`, `desks/journal.md`, `bench/lessons.md`.
- **Independent client-source checks:** every load-bearing API claim was re-checked with
  read-only `git -C /home/sam/wow-ui-source show origin/forever:<path>` (`origin/forever`
  available; checked-out branch there is `classic_era`, so `show` was used, never the
  worktree). Citations below are from that branch, not taken on trust from T1.

---

## 0. Verdict summary

| Brief section | Verdict | One-line basis |
|---|---|---|
| **A. Gate correctness** | **PASS** | Every new Forever behaviour is `st.family == "FOREVER"` **and** an exact API probe; `aura_icons.lua` is fully inert before any frame/event/aura call on all six non-Forever families; single-TOC contract holds. §3, §4. |
| **B. Secret-flow audit** | **PASS** (runtime closers UNCONFIRMED) | Zero secret reads on the restricted path: the opaque object is only handed to documented native sinks; every client read is nil/unknown-degraded or `NeverSecret`; no `GetText`/`GetFormattedText`/`GetRemainingDuration`-class read anywhere. The engine's acceptance of a secret-valued object from tainted code remains U3/U5 (in-client). §5, §7. |
| **C. Cache audit** | **PASS** | Every cache in the HUD/aura/LGC path is plain-by-construction or re-proves entries before use; no client value can become a table key unchecked; poisoned-entry legs fail their mutants. §6. |
| **D. Behaviour preservation** | **PASS** | Non-Forever numeric path is gated exactly as before (extra no-op probes only); pre-existing suites are intact by check-count arithmetic (893 / 177) and green; no aura-side interaction with HUD/bars/guide/practice visuals (`ST` surface = 5 read-only methods); defaults are data-only on classic. §8. |
| **E. Test & harness evidence** | **PASS** | `bash tests/run.sh` **59 steps, 0 failed**; `luacheck .` 2 warnings / 0 errors / 105 files (both pre-existing, `hunter_ui.lua:135-136`); `luac5.1 -p` clean; all 20 implementer mutants re-applied fail with their exact counts, t3's declared M5 survivor reproduces, and my extra `HasSecretValues` guard mutant fails too. §9. |
| **F. In-client checklist** | **DELIVERED** | §10 (exact `/run` lines + observation steps). Nothing in §10 is marked working by this report. |

**Bottom line.** Both lanes are evidence-backed and safe to keep. No secret value can reach
a comparison, arithmetic, string format, table key or table value on any path I could
trace, and no non-Forever client gains a frame, event, aura read, options surface, or
default-driven behaviour. Five low-severity findings (§7 F1-F5) are cosmetic/robustness
only; two informational deltas and two UNCONFIRMED runtime items follow them (F6-F9). One
runtime dependency of the *additive* GCD channel (probe spell 61304) is UNCONFIRMED and
does not affect the user-facing GCD. The remaining "is it working in the client" questions
are the U-probes in §10 — they cannot be closed offline and are not claimed closed here.

---

## 1. What I independently ran (exact outputs)

All from `/home/sam/SwedgeTimer`, 2026-11-08 22:23–22:45 ET.

| Command | Result |
|---|---|
| `bash tests/run.sh` | **59 steps, 0 failed**; `PASS luacheck . (Total: 2 warnings / 0 errors in 105 files)` |
| `luacheck . --no-color` | `Total: 2 warnings / 0 errors in 105 files` — `hunter_ui.lua:135:7 unused variable 'CAST_ZONE_SAFE'`, `hunter_ui.lua:136:7 unused variable 'CAST_ZONE_UNSAFE'` (file mtime 2026-11-06, untouched by either lane) |
| `luac5.1 -p` on `hud.lua compat.lua LibGlobalCooldown.lua aura_icons.lua main.lua config_presets.lua option_tables.lua option_table_presets.lua tests/hud_state.lua tests/forever_secret_compat_state.lua tests/aura_icons_state.lua tests/toc_check.lua` | all OK |
| `lua5.1 tests/hud_state.lua` | `PASS  hud_state.lua (1024 checks)` |
| `lua5.1 tests/forever_secret_compat_state.lua` | `250 checks, 0 failed` |
| `lua5.1 tests/aura_icons_state.lua` | `853 checks, 0 failures` |
| `lua5.1 tests/secret_guard_state.lua` (cross-lane, unmodified) | `PASS  secret_guard_state.lua (524 checks)` |
| `lua5.1 tests/toc_check.lua` | `360 checks, 0 failures` |
| Pre-existing-check arithmetic (see §9.1) | pre-t3 `hud_state` portion = **893 checks, 0 failures**; pre-t3 `forever_secret_compat_state` portion = **177 checks, 0 failed** (both match the implementers' stated baselines exactly) |
| Red-first re-proof (module absent) | `lua5.1 tests/aura_icons_state.lua` in a copy with `aura_icons.lua` deleted → **exit 1**, `cannot open tests/../aura_icons.lua: No such file or directory` (matches t4 §4.1) |
| Guard mutation (`HasSecretValues() ~= false` refusal removed at `compat.lua:398`) | **exit 1**: `forever_secret_compat_state` 4 failures — `HasSecretValues true: the all-zero degraded shape`, `…: fifth flags the restricted read`, `HasSecretValues nil: no duration is trusted`, `…fifth…` — i.e. the pre-existing object-reader guard **is** pinned |
| Line endings | every changed file LF-only (`grep -q $'\r'` negative); no mixed endings |
| Lint silencing | no `-- luacheck: ignore`, no `.luacheckrc` change (mtime 2026-10-15), no `_`-silenced globals in any changed file |
| File-touch audit | `find -newermt "2026-11-08 00:00"` outside `bench/desks/docs` returns exactly: `compat.lua`, `hud.lua`, `LibGlobalCooldown.lua`, `aura_icons.lua`, `main.lua`, `config_presets.lua`, `option_tables.lua`, `SwedgeTimer.toc`, `tests/run.sh`, `tests/toc_check.lua`, `tests/hud_state.lua`, `tests/forever_secret_compat_state.lua`, `tests/aura_icons_state.lua` — **plus one stray `luac.out`** (finding F2). `bars.lua`, `classes/*`, `config.lua`, `option_table_presets.lua`, `hud.lua`'s neighbours and every other test are older (2026-10-28 or earlier), matching both attestations. |

---

## 2. Independent client-source verification (origin/forever)

Each row was re-read from the branch, not accepted from T1.

| Claim used by the code | Verified at `origin/forever` | Verdict |
|---|---|---|
| `GetSpellCooldown` is secret-valued under cooldown restriction | `…/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua` `GetSpellCooldown` = `SecretWhenCooldownsRestricted = true` | confirmed |
| `GetSpellCooldownDuration` carries **no** `SecretWhen*` (so its handle is never secret) | same file, `GetSpellCooldownDuration` = `SecretArguments = "AllowedWhenTainted"`, no `SecretWhen*`, returns `LuaDurationObject` | confirmed |
| `SetCooldownFromDurationObject` has **no** `SecretArgumentsAddAspect` (unlike the four numeric setters) | `FrameAPICooldownDocumentation.lua`: `SetCooldown`/`SetCooldownDuration`/`SetCooldownFromExpirationTime`/`SetCooldownUNIX` each `SecretArgumentsAddAspect = { Enum.SecretAspect.Cooldown }`; `SetCooldownFromDurationObject(duration, clearIfZero)` = `IsProtectedFunction = true`, `SecretArguments = "AllowedWhenUntainted"`, **no aspect** | confirmed |
| `SpellCooldownInfo.isOnGCD` / `.isActive` / `.isEnabled` are `NeverSecret` | `SpellSharedDocumentation.lua`, `SpellCooldownInfo` fields `isEnabled`, `isActive`, `isOnGCD` each `NeverSecret = true` | confirmed |
| `LuaDurationObject:HasSecretValues` is `ReturnsNeverSecret`; the value getters (`GetRemainingDuration`, `GetTotalDuration`, `GetStartTime`, `IsActive`) are plain-argument but not `ReturnsNeverSecret` | `LuaDurationObjectAPIDocumentation.lua` (HasSecretValues `ReturnsNeverSecret = true`; the four getters `SecretArguments = "AllowedWhenUntainted"`, no conditional-secret marker) | confirmed — pessimistic treatment is correct |
| `C_Secrets.ShouldSpellCooldownBeSecret` exists and answers a plain bool | `SecretPredicateAPIDocumentation.lua` (`Namespace = "C_Secrets"`, `ShouldSpellCooldownBeSecret`, `ShouldAurasBeSecret`, `ShouldUnitAuraIndexBeSecret`) | confirmed |
| `C_DurationUtil.CreateDurationTextBinding`, `C_StringUtil.CreateSecondsFormatter`, `C_CurveUtil.CreateColorCurve` exist with no secret annotation | `DurationUtilDocumentation.lua`, `StringUtilDocumentation.lua`, `CurveUtilDocumentation.lua` | confirmed |
| Binding setters exist with the exact shapes used: `SetFontString(SimpleFontString)`, `SetFormatter(NumericFormatter)`, `SetDuration(LuaDurationObject)`, `SetUpdateInterval(number)`, `SetZeroDurationText(string|nil)`, `SetExpiredText(string|nil)`, `SetTextColorCurve(LuaColorCurveObject, DurationTextBindingProperty)`, `SetEnabled(bool)`, `Disable()`, `Enable()` | `DurationTextBindingObjectAPIDocumentation.lua` | confirmed |
| The formatter enum members used are real: `SecondsFormatterAbbreviation.None = 0`, `SecondsFormatterInterval.Seconds = 0`, `SecondsFormatterRounding.Truncate = 1`, `DurationTextBindingProperty.RemainingDuration = 0` | `SecondsFormatterSharedDocumentation.lua`, `DurationTextBindingSharedDocumentation.lua` | confirmed (so `compat.lua:671-685`'s configuration is valid, not a silent no-op) |
| Aura containers are created through `allowUntaintedCreation="true"` and groups require `DisableUntrustedLayoutScriptsTemplate` for later anchoring | `Blizzard_CustomAuraContainer.xml` (`<ScopedModifier allowUntaintedCreation="true"><AuraContainer name="CustomAuraContainerTemplate" …>`), `Blizzard_SharedXMLBase/ForbiddenAspectTemplates.xml:18`, `Blizzard_CustomAuraContainer.lua:286-327` (the `AddForbiddenAspects(UntrustedLayoutScriptExecution)` comment explicitly names `DisableUntrustedLayoutScriptsTemplate` as the opt-in) | confirmed |
| Container methods called by `aura_icons.lua` all exist: `SetSize`, `SetFrameStrata`, `SetUnit`, `AddAuraGroup`, `HasAuraGroup`, `SetAuraGroupLayout`, `SetEnabled`, `Show`/`Hide`/`SetPoint`/`ClearAllPoints`, `SetFlowLayoutAnchorPoint`, `SetFlowLayoutGrowthDirection`, `GetAuraGroupFrameCount`, `GetAuraGroupFrame` | `Blizzard_AuraContainer.lua:28,40`; `Blizzard_CustomAuraContainer.lua:286,330,335,348,409`; `Blizzard_AuraContainerFlowLayout.lua:19,31` | confirmed |
| `AddAuraGroup` option scheme matches the shipped options (`candidateFilters.includeSpellIDs`, `maxDuration`, `maxFrameCount`, `layout`, `initializeFrame`, `sortMethod`, `sortDirection`), `templateNames` optional (CustomAuraButtonTemplate always inherited) | `Blizzard_CustomAuraContainer.lua:20-190`, `Blizzard_AuraContainerShared.lua:127-150`, `Blizzard_AuraContainerFrameProviders.lua:60-90` | confirmed |
| `AuraContainerSortMethod.Expiration = 4`, `AuraContainerSortDirection.Normal = 0`, `_G.AuraContainerSortMethod`/`…Direction` exported with `securecopy` | `Blizzard_AuraContainerShared.lua:40-52,262-263` | confirmed |
| `AnchorUtil.FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 }` (matches both the passed and fallback values) | `Blizzard_SharedXMLBase/AnchorUtil.lua:471-477` | confirmed |
| Aura button inbound setters used by `style_button` exist: `SetIcon(Texture)`, `SetDurationText(FontString[, options])`, `SetApplicationCount(FontString[, options])`, `SetDurationBar(StatusBar[, options])`; options may be nil (Nilable=true, processors return defaults); `direction` is the documented duration-bar field | `Blizzard_CustomAuraButton.lua:87,159,178,224,243`; `AuraContainerUtilDocumentation.lua:71-160,316-334` | confirmed |
| `initializeFrame` runs **before** the client applies `DenyTaintedAccessWhenAurasAreSecret`, so the tainted style callback is not blocked | `Blizzard_AuraContainerFrameProviders.lua:88-102` ("Access restrictions should be applied after (potentially tainted) post-creation callbacks") | confirmed |
| The client sizes containers through `secretwrap`, so container geometry may be secret | `Blizzard_CustomAuraContainer.lua` layout path (the reference's `SetSize(secretwrap(w,h))` call site, T1/T2 §6) | confirmed by T2 and by the client's layout code; drives the "never measure" rule |
| `UnitExists`/`UnitCanAttack` return plain booleans (no secret return), so `hud_visible` is safe; `UnitGUID` is `SecretWhenUnitIdentityRestricted` (HUD's CLEU path) | `UnitDocumentation.lua` entries for all three | confirmed |
| `SetText` / `SetTextColor` stay callable with plain arguments after the Text aspect is attached (`AllowedWhenTainted`), only `GetText` becomes secret | `SimpleFontStringAPIDocumentation.lua:353-357,664-679` | confirmed — the numeric text face keeps working after a restricted episode |

**Where T1 was corrected or refined:** the trinket fourth-return claim (T1 §7) does not
describe this tree — `compat.lua:1760` reads three client values and adds its own SEC-10
flag; t3's deviation 1 is correct and no wrapper arity changed.

---

## 3. Gate audit — every Forever-only path and its gate

Legend: **FS** = `st.family == "FOREVER"`; **probe** = exact API/global presence test;
**delta** = what a non-Forever client can observe.

| # | Path | Gate | Non-Forever delta |
|---|---|---|---|
| 1 | `compat.lua:575` `api.get_spell_cooldown_duration` | FS + probe (`C_Spell.GetSpellCooldownDuration`) | one function definition; call answers `nil` after one string compare |
| 2 | `compat.lua:602` `api.get_spell_cooldown_state` | FS + probe (`C_Spell.GetSpellCooldown`) | same; never reads the info table |
| 3 | `compat.lua:625` `api.get_spell_cooldown_secrecy` | FS + probe (`C_Secrets.ShouldSpellCooldownBeSecret`) | same |
| 4 | `compat.lua:643` `api.create_duration_text_binding` | FS + probe | same |
| 5 | `compat.lua:659` `api.create_seconds_formatter` | FS + probe (`C_StringUtil.CreateSecondsFormatter`) | same; no formatter created |
| 6 | `compat.lua:694` `api.create_duration_text_color_curve` | FS + probe (`C_CurveUtil.CreateColorCurve` + `Enum.DurationTextBindingProperty`) | same; no curve created |
| 7 | `hud.lua:1399` `forever_native_enabled()` | FS + probe (`type(api.get_spell_cooldown_duration)=="function"`) | short-circuits at the family compare |
| 8 | `hud.lua:1407` `acquire_cooldown_object` | only reachable from `paint`'s `restricted and forever_native_enabled()` branch (`:1562`) | unreachable |
| 9 | `hud.lua:1428` `prepare_text_binding` / `:1470` curve / `:1497` release | object mode only; `release_text_binding` is a `nil`-check no-op without a binding | no-op |
| 10 | `hud.lua:1547` client secrecy predicate override | helper exists on every client but answers `nil` outside FOREVER; the branch then does nothing | one extra `pcall` + family compare per painted icon per tick (F6) |
| 11 | `hud.lua:1511-1541` SEC-13 probes (`api.is_secret`) | not family-gated by design (defence in depth); `api.is_secret` is `issecretvalue` where absent → always false | identical branch results |
| 12 | `hud.lua:954/1057` known-name/cache hardening, `:292-545` trinket poisoning | not family-gated by design; only bites when a secret exists | identical branch results |
| 13 | `LibGlobalCooldown.lua:193` `poll_gcd` object channel | FS + probe (`api.get_spell_cooldown_duration`) | block skipped at the family compare |
| 14 | `LibGlobalCooldown.lua:184` `clear_gcd_object` / `:175` release | fires only while the channel carries (never on classic) | no event |
| 15 | `aura_icons.lua:77-99` whole module | FS (`:78`) **then** `C_AuraContainerUtil`, `AuraContainerSortMethod`, `AuraContainerSortDirection` globals at load; `CreateFrame` probe at init | no frame, no event, no aura read, no option side effect (suite proves 0/0/0/0/0 per family) |
| 16 | `aura_icons.lua:1088` `A.init` | `available ~= true` return first; `main.lua:1059` seam is `pcall`-isolated and called once (`main.lua:1138`) | one table lookup + one call + one compare |
| 17 | `option_tables.lua:212-476` aura widgets | `hidden()` = `st.family ~= "FOREVER"` **and** `st.aura_icons.options_visible()` | 7 AceConfig args entries exist but are always hidden (0 rendered) |
| 18 | `config_presets.lua:141-145` defaults | unconditional (there is no per-family defaults mechanism) | 5 keys written into classic profiles; never read (module inert) — data-only, documented at `:133-140` |
| 19 | `SwedgeTimer.toc:67` | single TOC, all clients load the file | table/function definitions only (`aura_icons.lua:70-104` gate runs at load; pure reads) |

`st.is_mainline` alone gates **nothing** new: `grep -n "is_mainline"` in the changed files
returns only pre-existing lines (`hud.lua:786` CLEU validity, `compat.lua:131` GCD probe
spell, `compat.lua:482` the pre-existing SEC-12 item-object fallback). The one
duration-object *read* that is not Forever-gated is that pre-existing
`compat.lua:482` `st.is_mainline` fallback — it is safe by construction because it refuses
anything but `HasSecretValues() == false` first, and a mutation removing that refusal is
caught (§1).

---

## 4. Aura row inertness (the operator's "wow forever only")

Source-level (not only test-level):

- `aura_icons.lua` has **no** `UnitAura` / `C_UnitAuras` / `AuraData` / `GetPlayerAuraBySpellID`
  token at all (`grep` empty; suite also scans the source at `tests/aura_icons_state.lua:693-700`).
- The only `C_Secrets` reference is `A.aura_data_secret()` (`aura_icons.lua:1242`), used by
  `diagnostics()` only — it never gates the row.
- The only `ST` surface used is `get_bar_frame`, `iter_hands`, `get_class_table`,
  `get_profile_table`, `player_class` (`grep -o "ST[:.]…"`): **no** `show_bar`/`hide_bar`,
  no HUD frame, no `SetParent`, no `SetFrameLevel`, no `SetScale`. The module cannot move,
  resize, hide or re-parent any existing visual.
- Containers are only touched through the client API; every geometry read
  (`GetHeight/GetWidth/GetTop/GetBottom/GetLeft/GetPoint/GetSize/IsShown`) is absent from
  the module (`grep` empty). Bars are read with `IsShown`/`GetTop` only, both pcall'd and
  `is_secret`-guarded (`aura_icons.lua:618-639`, selector `:985-1009`).
- Combat: `A.init` defers native containers while `InCombatLockdown()` (`:1135-1140`); the
  only frame created then is a plain `Frame` driver (`:898-929`), which is allowed.

Suite evidence: all six non-Forever families get `available=false`, `gate()=="family"`,
`init` false, **0 frames / 0 events / 0 `AuraContainer` attempts / 0 aura reads / 0 secrecy
predicate calls** (`tests/aura_icons_state.lua:552-575`); removing the family gate (mutant
T4-M1) fails **55** checks.

---

## 5. Secret-flow audit (Forever)

### 5.1 The restricted cooldown path

```
provider flags restricted
  → HUD.paint: restricted := (plain probe of every field) or provider flag or
    C_Secrets.ShouldSpellCooldownBeSecret(slot spell)                      hud.lua:1521-1555
  → api.get_spell_cooldown_duration(spell, false)                          compat.lua:575-600
      pcall C_Spell.GetSpellCooldownDuration; read object.HasSecretValues (plain); never a value
  → object → CooldownFrame:SetCooldownFromDurationObject(object, true)     hud.lua:1562-1588
  → api.get_spell_cooldown_state(spell) → isOnGCD/isActive (NeverSecret)   compat.lua:602-623
  → binding = api.create_duration_text_binding()                           compat.lua:643-657
      SetFontString(icon.text) / SetFormatter(plain config) / SetUpdateInterval(0.05)
      SetZeroDurationText("") / SetExpiredText("")                         hud.lua:1428-1468
  → binding:SetTextColorCurve(step curve, RemainingDuration)               hud.lua:1470-1495
  → binding:SetDuration(object); SetEnabled(true)                          hud.lua:1662-1668
  → cache: icon.cd_object = handle; icon.text_value = nil                  hud.lua:1573 and :1674
```

**No number is ever read out of the object.** Proof, three independent ways:

1. `grep` for `GetRemainingDuration|GetTotalDuration|GetStartTime|HasStarted|HasExpired|IsActive`
   in product files returns **only** `compat.lua:394-396` — inside
   `read_cooldown_duration_object`, which refuses unless `HasSecretValues()` is exactly
   `false` (`compat.lua:385-400`). `hud.lua`, `aura_icons.lua` and `LibGlobalCooldown.lua`
   contain **zero** object getter calls (also zero `IsZero()`).
2. The t3 fixtures make every getter `error()` (`tests/hud_state.lua:3390-3400`) and the
   object still paints (1024 checks green) — any read would be a loud failure.
3. My own probe (§1, "Guard mutation") plus the scratch V1 experiment: with
   `HasSecretValues() == true` and **every getter raising**, `api.GetSpellCooldown` degrades
   to `0,0,0,0,true` and `api.get_spell_cooldown_duration` returns the handle + `true`
   without calling any getter — **259 checks, 0 failed**.

Also verified absent from the whole restricted path: `SecondsFormatter:Format`,
`NumericFormatter:FormatNumber`, `LuaDurationObject:FormatRemainingDuration`,
`GetFormattedText`, `GetText`, `string.format` on any client value, `secretunwrap`
(removed from the addon environment on this branch). `grep` for
`GetFormattedText|GetText|:Format(` in `hud.lua compat.lua LibGlobalCooldown.lua
aura_icons.lua` returns **comments only** (`compat.lua:641-642`).

### 5.2 Read-by-read matrix (brief §B list)

| Client surface | Where in the changed path | Restricted answer | Where the value goes | Verdict |
|---|---|---|---|---|
| `C_Spell.GetSpellCooldown` | `compat.lua:432-478` (compat wrapper), `:602` state helper; `hud.lua:1547` only through compat | timing fields secret | compat asks `is_secret` on each field, degrades to `0,0,0,0,true`; the HUD branches only on the plain never-secret fields | safe |
| `C_Spell.GetSpellCooldownDuration` | `compat.lua:575`; `hud.lua:1407`; `LibGlobalCooldown.lua:193-215` | opaque handle (non-secret) | `SetCooldownFromDurationObject`, `DurationTextBinding:SetDuration`; handle stored in `icon.cd_object` / `lib.gcd_object` | safe |
| `C_ActionBar.GetActionCooldownDuration` | not used by either lane | — | — | n/a |
| `GetInventoryItemCooldown` | `compat.lua:1760-1786`; `hud.lua:376,480` | wrapper returns `0,0,0,true` | trinket tri-state (`nil` = unknown keeps the slot grey) — SEC-10 unchanged | safe |
| `C_Spell.GetItemCooldown` | not used | — | — | n/a |
| `UnitAura` / `C_UnitAuras.*` | trinket proc scan `hud.lua:343` through `api.UnitAura` (`compat.lua:981-1027`) | per-index `C_Secrets.ShouldUnitAuraIndexBeSecret` precheck then per-entry secret rejection → `nil` | scan treats `nil` as "no match"; the write boundary re-proves `expires`/`duration` | safe; **aura row reads none at all** |
| `C_Spell.GetSpellInfo` | `hud.lua:983` (cache name), `paint` texture lookup not present | `C_Spell.GetSpellInfo` has no `SecretWhen*`; the wrapper's cached name is re-proved | `HUD.known_names` write only when the name is proven plain | safe |
| `IsSpellUsable` | `compat.lua:758-776` (pre-existing) | returns `nil` on secret | HUD tint guarded by `usable_unknown` | safe |
| `UnitPower` / `UnitHealth` | not in either lane's files | — | — | n/a |
| `UnitGUID` | `hud.lua:430` (`on_aura_applied`, CLEU) | — | CLEU is never registered on Forever (`hud.lua:786` `valid = not st.is_mainline`) | unreachable on Forever |
| `UnitIsUnit` / `UnitCreatureType` | not in either lane's files | — | — | n/a |
| `UnitExists` / `UnitCanAttack` | `hud.lua:911-912` (`hud_visible`) | plain bools (no `SecretWhen*` on the branch) | boolean visibility decision | safe |
| `C_Secrets.*` | `compat.lua:359-366, 625-641`; `aura_icons.lua:1242` | plain bool / enum | branching only; `aura_data_secret` is diagnostics-only | safe |
| `C_DurationUtil`, `C_StringUtil`, `C_CurveUtil` | `compat.lua:643-737` | no secret surface (no `SecretWhen*` on any of the three factories) | handles + plain config | safe |
| Aura container geometry (`GetHeight/Top/…`) | never called (`grep` empty) | might be secret | not read | safe by construction |
| Aura button inbound setters (`SetIcon`, `SetDurationText`, …) | `aura_icons.lua:680-730` | plain widget handles only | the client writes icon/text/stacks/bar itself | safe |
| `GetAuraGroupFrameCount`/`GetAuraGroupFrame` | `aura_icons.lua:810-829` | count treated as possibly secret → skipped | resize skipped, never compared | safe |
| `UnitRace` | `aura_icons.lua:587-605` | secret-guarded; a secret token adds no racial id | list build (racial merge) | safe |

### 5.3 Boolean-field discipline in `paint` (SEC-13)

`paint` probes `hidden`, `restricted`, `remaining`, `duration`, `text_remaining`, `start`,
`usable`, `in_range`, `glow`, `desaturate`, `reverse`, `texture` **before** any branch
(`hud.lua:1511-1541`); a secret `hidden` draws nothing, a secret timing field forces the
restricted face, a secret cue resolves to "no cue". The state scrub
(`hud.lua:1842-1898`) protects `update_display`'s own branches (`if s and not s.hidden`,
`not preview`) before they run (`hud.lua:1943`). Tested by `tests/hud_state.lua:3733-3783`
(poisoned booleans, poisoned `hidden`, poisoned texture, poisoned whole provider state).

**M5 disclosure (accepted):** removing the scrub (`hud.lua:1943`) is **not** caught offline
(0 failures) because Lua 5.1 cannot make a comparison on a flagged primitive raise — exactly
as t3 reported. My assessment: the scrub is still the only guard for `update_display`'s own
booleans on the real client, and its paint-boundary twins are mutation-proven (M2, M7). It
should stay; nothing should claim it is offline-proven.

---

## 6. Cache audit (the operator's specific worry)

| Cache | Stored | Can it be secret? | Revalidation before use | Test that pins it |
|---|---|---|---|---|
| `HUD.known_names` id→name (`hud.lua:945`) | plain string | yes in principle (spell names can turn secret under the Text/aura aspects) | a secret spell id returns **before** the cache key/query (`:963-967`); a cached name is `is_secret`-proven and dropped (`:976-981`); a secret `GetSpellInfo` answer is never written (`:983-988`) | `tests/hud_state.lua:3622-3664`; mutant T3-M3 → 1 check fails (`known_names: a secret spell id is never a cache key`) |
| `known_cache` / `HUD.known_cache` slot→`{at,value}` (`hud.lua:1049-1095`) | plain number + plain boolean | a poisoned entry could carry a secret | entry `type`+`is_secret` re-proved on **both** fields before the TTL read, poisoned entry deleted (`:1065-1078`); a secret answer or clock is never written (`:1084-1094`) | `hud_state:3650-3673`; mutant T3-M4 → 3 failures |
| `HUD.layout_cache` (`hud.lua:744,1296-1330`) | saved-variable values only (`LAYOUT_KEYS`) | no client read enters it | n/a (plain db) | pre-existing layout tests |
| `HUD.icons[i].cd_start/cd_duration/cd_reverse` | plain numbers, only on the readable path | no | written only when `restricted == false` (all timing fields proven plain at `:1525-1534`); object mode nils them (`:1574`) | `hud_state:3420-3505`; mutants M1/M2/M7 |
| `HUD.icons[i].cd_object` | opaque handle | **no** (non-secret handle) | never read; re-acquired per restricted tick | `hud_state:3415-3448` |
| `HUD.icons[i].text_value/text_color/text_hidden` | plain derived values | no | nils when the native binding owns the string (`:1670-1674`), rebuilt after release | `hud_state:3455-3470` |
| `HUD.icons[i].text_binding` / `text_curve_key` | binding handle; `{warn_color, normal_color}` from db | no | curve rebuilt only on a db colour change | `hud_state:3443-3452` |
| `HUD.trinkets[13/14]` (`:292-463`) | item id, buff id, icd, texture, expires stamps | yes in principle | whole record dropped when any field is secret **before** any compare (`:292-300`, `:471-475`); aura/proc writes re-proved (`:350-357`); the four cooldown returns re-proved before the 1.5 s filter (`:479-487`, `:519-522`) | `hud_state:3675-3696`; pre-existing SEC-10 legs |
| `TRINKET_STATE` / `PREVIEW_STATE` / `SAFE_STATE` (`:238`, `:239`, `:1840`) | reused plain tables | no | reset lists include `restricted` (`:1791`, `:1957`); `SAFE_STATE` re-filled from plain fields only | `hud_state:3700-3728`; mutant M2 |
| `LibGlobalCooldown.gcd_duration/gcd_started/gcd_expires` | plain numbers | no | `plain_number` refuses secret/non-finite (`LibGlobalCooldown.lua:53-66`); a restricted read **clears** instead of storing (`:227-232`) | `hud_state:3843-3862`; mutant M6 |
| `LibGlobalCooldown.gcd_object/gcd_on_gcd` | handle + plain never-secret bool | no | never read; cleared on the plain state (`:184-191`) | `hud_state:3806-3841` |
| `current_spell_gcd/current_spell_haste/phys_gcd/base_spell_gcd` | plain numbers from guarded reads | no | `read_combat_rating*` nil on secret (`:41-51`) | pre-existing |
| `aura_icons` state (`A.state.*` `:176-195`) | frame handles, plain numbers, spell-id lists | no | `bar_top` proven plain+finite (`:629-637`); secret `IsShown`/`GetTop` skipped; frame count treated as possibly secret (`:810-820`) | `aura_icons_state:1050-1080`; mutant T4-M9 |
| `compat.lua` tables | `api` (functions) + `spell_known_probes` (function refs) + the clock offset | no | no value cache exists; the clock offset is `GetTime`/`GetTimePreciseSec` only | pre-existing |

No table in the changed surface can receive a secret **key**: the only client-derived keys
are `HUD.known_names[spell]` (spell proven plain first), `known_cache[slot]` (internal slot
table), and `includeSpellIDs` keys (literal ids). `aura_icons` never indexes by a client
string (`racial_ids` refuses a secret token before `A.RACIAL[token]`, `:553-561`).

---

## 7. Findings

Ranked; none is a blocker and none is a secret/taint defect. I did not fix any of them.

### F1 — low — comment typos in the new module header
`aura_icons.lua:4` reads `-- WO W FOREVER ONLY.` and `:11` reads `--   * a HELP FUL row on
unit "player"`. **Degraded input:** none (comments). **Current behaviour:** none.
**User effect:** none — but this file is the operator-facing description of the Forever-only
contract. **Minimal fix:** two one-word edits (`WOW`, `HELPFUL`). **Test that would pin it:**
none needed; a docs/typo pass.

### F2 — low (housekeeping) — stray compiled bytecode in the addon root
`luac.out` (8 845 bytes, Lua 5.1 bytecode compiled from `LibGlobalCooldown.lua`, mtime
2026-11-08 21:49) sits in the repository root. It is **not** listed in `SwedgeTimer.toc`, so
no client can load it, and it is not referenced by any test. **User effect:** none; it is
release-tree litter that a packaging step would ship. **Minimal fix:** delete it (Lead owns
the working tree; this lane is read-only). **Test that would pin it:** a packaging check
that only TOC-listed files ship, if the release process has one.

### F3 — low (robustness) — a setup failure after a successful `CreateFrame` can make the row permanently unbuildable for the session
`aura_icons.lua:735-748` creates the container with a **global name**
(`SwedgeTimerAuraIconsBuffs` / `…Debuffs`); `:944-953` then runs
`container:SetSize/SetFrameStrata/SetUnit` in a pcall. If that setup pcall fails, the frame
is hidden but the global name stays registered, `state.container` stays `nil`, and the next
retry calls `CreateFrame` with the same name — which errors on the real client ("frame with
that name already exists"), so `create_container` returns `nil` forever and the row never
appears (no latch, but no success either; `diagnostics().error == "container:buffs"`).
**Degraded input:** an invalid `db.frame_strata` string in a hand-edited/legacy profile
(`strata_for`, `:470-478`) — no current option writes that key, so this is a very unlikely
trigger; an injected `SetSize`/`SetUnit` failure is the other path. No secret or taint
implication. **Minimal fix:** on a setup failure either clear the name
(`container:SetName(nil)` isn't available — use `_G[row.container] = nil` after
`container:Hide()`, or create unnamed and assign the name after setup), or have
`create_container` reuse `_G[row.container]` when it exists. **Test that would pin it:** a
suite leg that injects a one-shot setup failure and asserts the *next* attempt still builds
(the fake client currently has no duplicate-name check and no setup-failure injector).

### F4 — low (cosmetic, secret-state edge) — a size change made while auras are secret can leave already-allocated buttons at the old size
`aura_icons.lua:810-829` `resize_group_frames` calls `frame:SetSize` on client-owned aura
buttons with `pcall`. Under `DenyTaintedAccessWhenAurasAreSecret` (the client's
`AccessRestrictionFlags`, `Blizzard_AuraContainerShared.lua`) that call may be denied while
auras are secret; the failure is contained (`layout_error = "layout"`), but `sync_layout`
still records the new size (`:861-895`), so the pass will not retry and the buttons keep the
old edge length until the next size change. Newly created buttons do use the new size
(`:684` reads `current_icon_size`, `:686` calls `SetSize`). **User effect:** a mixed-size row for the rest of that
secret window after dragging the size slider mid-fight. **Minimal fix (optional):** don't
commit `A.state.layout.size` when `resize_group_frames` failed, so the next 0.15 s pass
retries; or re-push the layout on the next secret-state transition. **Test that would pin
it:** the fake `GetAuraGroupFrame` button must be able to deny `SetSize`, then the suite
asserts the next pass retries. In-client observation is in §10 (row 7).

### F5 — low (report accuracy) — "6 additional hidden widgets" is 7 AceConfig entries
`bench/aura_row_2026-11-08.md:151` says "6 additional hidden widgets in the Behaviour options
page". The builder returns **7** args (`aura_icons_header`, `aura_icons_desc`,
`aura_icons_enabled`, `aura_icons_show_debuffs`, `aura_icons_size`, `aura_icons_spacing`,
`aura_icons_grow`, `option_tables.lua:265-403`), all hidden on non-Forever (header +
description + 5 controls = 2 non-interactive + 5 controls). **User effect:** none; the
non-Forever delta is 7 hidden table entries, 0 rendered controls. **Minimal fix:** correct
the sentence when the report is next touched (reports are append-only; a note is enough).

### F6 — info (benign non-Forever delta) — one extra `pcall` + family compare per painted icon per tick
`hud.lua:1547` runs `pcall(api.get_spell_cooldown_secrecy, spell)` on **every** client
because the compat helper exists everywhere (it answers `nil` outside FOREVER). With ~20
icons at 20 Hz that is ≈400 pcalls/s plus ~10 `api.is_secret` no-op probes per icon/tick.
No behavioural difference (all guards evaluate false); measured cost is far below the
existing per-tick work (`HUD.spell_known_allows`, provider calls). Recorded so a later perf
lane does not have to rediscover it; no action recommended.

### F7 — UNCONFIRMED (runtime, the one real risk) — does the engine accept and render a secret-valued `LuaDurationObject` from tainted code?
The documented annotations say yes (no `SecretWhen*` on the reader, no
`SecretArgumentsAddAspect` on the sink) and Blizzard's own aura pipeline passes such
objects (§2), but only a Forever client can settle U3 (engine acceptance) and U5 (native
rendering/text). Every call is `pcall`-guarded with the grey unknown face as fallback, so a
refusal degrades rather than throws. Closers: §10 probes 4, 5, 7.

### F8 — UNCONFIRMED (runtime, additive channel only) — `LibGlobalCooldown`'s object channel probes spell 61304
`st.gcd_probe_spell_id = 61304` on Mainline-code clients (`compat.lua:131-133`). If that id
does not exist on Forever, `api.get_spell_cooldown_state`/`get_spell_cooldown_duration`
decline, `GCD_OBJECT_STARTED` never fires, and `lib.gcd_object` stays `nil`. **No consumer
exists** (grep: zero references outside `LibGlobalCooldown.lua` and tests), and the HUD's
own GCD does not depend on it (each icon's own object with `ignoreGCD=false`), so the
user-facing GCD is unaffected. Closer: §10 probe 2/3.

### F9 — info (accepted limitation, disclosed by t3) — mutant M5 (state scrub removed) survives offline
Reported, not hidden. Keep the scrub; it is the only protection for `update_display`'s own
branches on the real client. The in-client grey-face probes (§10, rows 5-6) are how it gets
observed.

---

## 8. Behaviour preservation (non-Forever)

1. **Numeric cooldown path.** In `HUD.paint` the numeric swipe is still
   `if not object_mode and not restricted and s.duration and s.duration > 0 and (s.remaining
   or 0) > 0` with the same set-once `cd_start/cd_duration/cd_reverse` comparison, the same
   suppression flags, `SetReverse` then `SetCooldown(start, duration)` then `Show()`
   (`hud.lua:1611-1636`); the clear branch is unchanged (`:1637-1650`). The new
   `not restricted` term is false on every classic client (no secret values exist), so the
   sequence is identical. Mutant T3-M1/M2 and the suite's section 24 (`hud_state:3531-3560`)
   pin `duration_object_reads == 0`, `cooldown_sink_calls == 0`, one `SetCooldown`,
   `cooldown_start == 295`, `cooldown_duration == 10`, set-once across ticks.
2. **Text rules.** The numeric text block (`hud.lua:1694-1736`) is unchanged: quantised
   rebuild, `WARN_SECONDS = 3` warn colour, `GCD_TEXT_HIDE = 2` hide rule, frame-level raise
   on show. `release_text_binding` is a no-op without a binding.
3. **Tints/glow/desaturate.** Same expressions, with `not desat_unknown` / `not
   usable_unknown` / `not range_unknown` / `not glow_unknown` terms that are always true on
   classic clients (`:1737-1784`).
4. **Trinket tri-state (SEC-10).** Unchanged: restricted read → `nil` → slot kept, grey, no
   countdown, one-session notice (`hud.lua:461-545`); readable passive still hides
   (`hud_state:3689-3712`).
5. **LibGlobalCooldown numeric semantics.** Readable GCDs arm exactly as before
   (`hud_state:3790-3800`); a restricted read now clears instead of storing a partial
   (`:3843-3862`); the new events have no consumers, so `ST.gcd` consumers are untouched.
6. **Aura row vs existing visuals.** The module's only `ST` calls are read-only getters
   (§4); it creates only its own driver + 2 containers; the suite asserts the swing bars are
   never shown/hidden by it (`aura_icons_state:1272`). No HUD icon, bar, power bar, guide or
   practice visual is touched.
7. **Defaults.** `config_presets.lua:141-145` adds 5 keys to the shared class defaults. No
   per-family defaults mechanism exists, so classic profiles hold 5 unreachable keys
   (documented at `:133-140`); nothing reads them because the module's gate is false and the
   option widgets are hidden. Behaviour: unchanged.
8. **Combat safety.** No native container is created under `InCombatLockdown()`
   (`aura_icons.lua:1135-1140`); the driver is a plain Frame; every container `Show/Hide/
   SetPoint` is `pcall`-isolated and retried on the next 0.15 s pass; the HUD creates no new
   frames. No secure/protected call is made on a protected frame.

---

## 9. Test-quality audit

### 9.1 The pre-existing checks were not weakened (check-count arithmetic)

I truncated the new sections out of **copies** of the two extended suites and ran them
against the current tree:

- `tests/hud_state.lua` minus lines 3377-3866 → **`PASS hud_state.lua (893 checks)`**,
  0 failures. The implementer's stated pre-t3 baseline is exactly 893 and the new sections
  claim exactly +131 → **1024** (current run: 1024). A deleted or newly-vacuous old check
  would show a lower total.
- `tests/forever_secret_compat_state.lua` minus lines 856-1082 → **`177 checks, 0 failed`**
  (stated baseline 177; new 250 = +73).

Residual: without VCS history (no git in this lane) I cannot byte-diff the pre-existing
section; the count parity plus all checks green is the strongest available offline evidence.

### 9.2 Mutation re-run (independent, current tree, isolated copies)

Each mutant was applied to a fresh copy (`.git`, Media/Images/Sounds/docs/bench/desks,
`.agent-teams` excluded), the suite run from the copy root, the source file restored from
the real tree afterwards, and the copy deleted — all inside one shell call (a bash call here
gets a private `/tmp`, the trap T1/t3 recorded). Anchors were asserted unique before the
write; every mutant failed **for its intended assertion** (spot-checked failure text below).

| # | Mutant | Suite | My result | Implementer's claim |
|---|---|---|---|---|
| T3-M1 | object path disabled (`if restricted and forever_native_enabled()` → `if false and …`) | hud_state | **34 / 1024 fail, exit 1** | 34 |
| T3-M2 | restricted painted as readable (`restricted = false`) | hud_state | **41 / 1024, exit 1** | 41 |
| T3-M3 | secret spell id accepted as a cache key | hud_state | **1 / 1024, exit 1** — `known_names: a secret spell id is never a cache key` | 1 |
| T3-M4 | `known_cache` revalidation disabled | hud_state | **3 / 1024, exit 1** | 3 |
| T3-M5 | state scrub removed | hud_state | **0, exit 0 — SURVIVES** (declared; §7 F9) | 0 (declared) |
| T3-M6 | LGC object-channel gate disabled | hud_state | **11 / 1024, exit 1** | 11 |
| T3-M7 | SEC-12 numeric secret re-check removed | hud_state | **6 / 1024, exit 1** — `SEC-12: a leaked secret state clears the swipe (got 424243, want 0)` | 6 |
| T3-M8 | FOREVER gate removed from `api.get_spell_cooldown_duration` | forever_secret_compat_state | **4 / 250, exit 1** — `fduration TBC/Retail: no duration object` + `the client reader is never called` | 4 |
| T3-M9 | client secrecy predicate override disabled | hud_state | **2 / 1024, exit 1** | 2 |
| T4-M1 | family gate branch deleted | aura_icons_state | **55 / 853, exit 1** — `ERA: available is false (got true, want false)` | 55 |
| T4-M2 | debuff filter loses `|PLAYER` | aura_icons_state | **2 / 853, exit 1** | 2 |
| T4-M3 | topmost comparator inverted | aura_icons_state | **15 / 853, exit 1** | 15 |
| T4-M4 | fixed band replaced by `debuff_container:GetHeight()` | aura_icons_state | **9 / 853, exit 1** — `the containers are NEVER measured (got 1, want 0)` | 9 |
| T4-M5 | shared-buff merge dropped | aura_icons_state | **11 / 853, exit 1** | 11 |
| T4-M6 | permanent latch on creation failure | aura_icons_state | **4 / 853, exit 1** | 4 |
| T4-M7 | 27019 re-added to hunter debuffs | aura_icons_state | **4 / 853, exit 1** | 4 |
| T4-M8 | 0.15 s throttle removed | aura_icons_state | **2 / 853, exit 1** | 2 |
| T4-M9 | secret `GetTop` guard dropped | aura_icons_state | **3 / 853, exit 1** — `selector: secret geometry cannot choose a bar (got table, want nil)` | 3 |
| T4-M10 | option widgets ignore family | aura_icons_state | **5 / 853, exit 1** — `options: aura_icons_enabled is hidden on Era` | 5 |
| T4-M11 | `post_init` seam call deleted | aura_icons_state | **2 / 853, exit 1** | 2 |
| T4-M12 | `aura_icons.lua` TOC line deleted | aura_icons_state | **3 / 853, exit 1** | 3 |
| V-guard | `HasSecretValues() ~= false` refusal removed (`compat.lua:398`, pre-existing object reader) | full harness | **2 suites fail, exit 1** — the four `HasSecretValues` legs listed in §1 | (not in either lane's table) |

All 21 implementer-claimed mutants reproduce **exactly** (same counts, same suites), the
declared survivor reproduces, and my extra guard mutant shows the pre-existing object reader
**is** pinned (so an "untested secret path" worry there is unfounded). No mutant fails for
the wrong reason: each spot-checked failure names the mechanism it breaks.

### 9.3 New-check quality

- Every new check is a real assertion (`check`/`eq`/`near` against a captured fake-client
  call or a source fact); `grep` finds no `assert(true)` / `check(true` in the new files.
- The two suites that matter are red-first (module absent → load error, exit 1 — re-proven
  in §1; t3's code lives in existing files, so its red-first equivalent is the mutation
  table).
- Booby traps are in place: `UnitAura`/`C_UnitAuras.*` raise on any call
  (`aura_icons_state:326-333`); container geometry getters count and can raise
  (`:216-244`); the duration-object stub raises on every getter (`hud_state:3390-3400`);
  the aura-row button/icon setters can raise (`:80-125`).
- Registration is single: `aura_icons_state.lua` one line in `tests/run.sh:77`; one
  `REQUIRED_MODULES` pin in `tests/toc_check.lua:402`; `hud_state`/`forever_secret_compat`
  one line each.
- LF only, no CRLF, no lint-config change, no `luacheck: ignore`, no `_`-silenced warning in
  any changed file.

---

## 10. In-client checklist (WoW Forever / Camelot, 1.60.1 (70790))

Nothing below is claimed working by this report. Run `/st diag` once per session so each
observation is attributable; `SwedgeTimer` is the AceAddon global.

### 10.1 Secrecy / API probes (`/run` lines, copy-paste)

1. `/run print("restrictions", C_Secrets.HasSecretRestrictions(), "cd", C_Secrets.ShouldCooldownsBeSecret(), "auras", C_Secrets.ShouldAurasBeSecret())`
   → expect plain booleans; record them.
2. `/run print("glyph", 61304, C_Secrets.GetSpellCooldownSecrecy(61304), C_Secrets.ShouldSpellCooldownBeSecret(61304))`
   → if the spell prints as a name and the secrecy answers, the LGC object channel can arm
   (closes F8/U7). Out of combat and during a GCD, twice.
3. `/run local d=C_Spell.GetSpellCooldownDuration(61304,false) local i=C_Spell.GetSpellCooldown(61304) print("gcd", type(d), issecretvalue(d), d and d:HasSecretValues(), i and i.isOnGCD, i and i.isActive)`
   → idle vs during a GCD; expect `table false true/false <bool> <bool>` (closes U6).
4. `/run local c=CreateFrame("Cooldown",nil,UIParent,"CooldownFrameTemplate") c:SetSize(64,64) c:SetPoint("CENTER") local d=C_Spell.GetSpellCooldownDuration(20271,false) print("sink", pcall(function() c:SetCooldownFromDurationObject(d,true) end))`
   at the target dummy **in combat** → `true`; the frame then sweeps (closes U3).
5. `/run local b=C_DurationUtil.CreateDurationTextBinding() local f=UIParent:CreateFontString(nil,"OVERLAY") f:SetPoint("CENTER") b:SetFontString(f) b:SetFormatter(C_StringUtil.CreateSecondsFormatter()) b:SetUpdateInterval(0.05) b:SetDuration(C_Spell.GetSpellCooldownDuration(20271,false)) b:Enable() print("binding", b:HasSecretValues(), pcall(b.GetFormattedText,b))`
   → a countdown is visible on the FontString (closes U5); `GetFormattedText` may be secret —
   that is informative, the addon never calls it.
6. `/run local d=C_Spell.GetSpellCooldownDuration(20271,false) print("getters", d:HasSecretValues(), pcall(d.GetRemainingDuration,d), issecretvalue((select(2,pcall(d.GetRemainingDuration,d)))))`
   → confirms why the addon never calls the getters (U4).
7. `/run local A=SwedgeTimer.aura_icons; print("globals", type(C_AuraContainerUtil), type(AuraContainerSortMethod), type(AuraContainerSortDirection)); print("diag", A and A.diagnostics().available, A and A.diagnostics().ready, A and A.diagnostics().error)`
   → `table table table`, then `true true nil` after login (closes U12 + F3 check).
8. `/run local A=SwedgeTimer.aura_icons; local d=A.diagnostics(); print("rows", d.buff, d.debuff, d.buff_shown, d.debuff_shown, d.bar, d.attempts, d.anchor_error, d.layout_error)`
   → `true true true true true 1 nil nil` with a visible swing bar.
9. `/run print("strata", SwedgeTimer:get_profile_table().frame_strata)` → must be `nil` or a
   valid strata name (`MEDIUM`, `HIGH`, …). A garbage value is the F3 trigger; if it is
   garbage, the row may never build — report it.
10. `/run local f=CreateFrame("AuraContainer",nil,UIParent,"CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate"); print("create", tostring(f))`
    → a frame, not `nil` (closes U1; proves the tainted-creation declaration holds).

### 10.2 Cooldown / GCD behaviour (Forever, in a dungeon/instance so the regime is on)

1. Pull a boss; cast the class's main ability on cooldown. Expect: the icon **swipes**
   (native), and a countdown appears above the icon except while the GCD itself is
   sweeping (the 2 s rule uses `isOnGCD`). No Lua error / BugSack entry on start or end.
2. Watch a cooldown end during combat: the swipe clears at zero and the icon un-greys at
   the same tick; no stale swipe, no fabricated "ready".
3. Watch the GCD sweep the whole icon row (each icon's own object with `ignoreGCD=false`).
4. In a restricted state, type `/run local A=SwedgeTimer.aura_icons; print(A and 1)` and
   check the HUD keeps updating (no protected-action spam, no taint error).
5. Restricted text colour: hold a short cooldown at <3 s → the native text should be
   red/warn (db colour) via the curve; record whether it matches the readable-state colour.
6. Leave combat/instance: icons return to the exact readable face (custom text format,
   warn colour, set-once swipes). This is the "byte-identical numeric face" check.
7. With auras secret (in combat): open `/st` → Behaviour → change **Icon size** while
   restricted; observe whether already-shown aura icons resize (F4). Also drag a swing bar
   in combat and confirm the row follows or re-anchors out of combat with no blocked-action
   errors (`diagnostics().anchor_error == nil`).

### 10.3 Aura row (per class)

1. With a visible swing bar and a temporary buff up, the buff icon appears within ~0.15 s,
   above the topmost visible bar; icon border, duration text and stack count update.
2. Two same-class players apply the same debuff to one hostile mob → exactly **one** icon
   (yours; the client filters the other). Target a friendly player → the debuff row is
   empty by the client's own identity rule (not a bug).
3. Toggle hands/bars (`/st` → bars), drag the top bar: the row re-anchors to the highest
   *visible* bar within one pass. With the class master switch off (all bars hidden), the
   row hides within one pass.
4. `/st` → Behaviour → "Aura icons (WoW Forever)": controls present on Forever only; the
   toggle hides/shows the rows immediately; size/spacing re-layout; direction flips the row
   origin; `/reload` keeps the values.
5. Racial buff (e.g. Blood Fury) appears once; a stance/aspect/seal icon never appears in
   the row; `C_Spell.GetSpellInfo(27019)` is `nil` on Forever (excluded TBC rank).
6. **Non-Forever client** (any Era/TBC/Wrath/Cata/Mists/Retail): log in, `/st` → Behaviour
   has no "Aura icons" section; no aura frames exist; nothing changes visually versus the
   previous build. (Offline this is proven; the in-client pass is a sanity check.)
7. Whole-row visual check: HUD + guide + aura row on screen with all six classes on
   Forever — confirm no overlap with the guide/power bar; if they collide, raise the aura
   offset default (out of this lane).

### 10.4 What remains UNCONFIRMED (cannot be marked "fully working" by the team)

U3 (engine accepts a secret-valued object from tainted code), U5 (native rendering of a
secret-valued object/text), U4 (getter secrecy — informational), U6/U7 (per-spell vs
per-probe GCD object behaviour and 61304's existence), U1 (tainted container creation), U8
(container `SetPoint`/`Show`/`Hide` in combat under forbidden aspects), the friendly-target
debuff-emptiness rule, the F4 resize-under-secrecy edge, and every journaled T2 §13 item.
They are opened **only** by the probes in §10.1 and the observations in §10.2/§10.3.

---

## 11. Residual risk register

| Risk | Likelihood | Impact | Mitigation in place | Closer |
|---|---|---|---|---|
| Engine refuses a secret-valued object from tainted code (U3) | low (annotations + Blizzard's own pipeline say yes) | restricted swipe stays grey (today's behaviour) — no error | every sink is `pcall`-guarded; `unknown_face` grey fallback | §10.1 probe 4 |
| Native text binding does not render for a secret object (U5) | low | restricted countdown absent; swipe still real | binding failure is latched per icon and costs only the text | §10.1 probe 5 |
| 61304 absent on Forever (F8) | medium | LGC object events never fire — no consumer today | HUD GCD uses each icon's own object | §10.1 probes 2-3 |
| Invalid `db.frame_strata` triggers F3 | very low (no writer of that key in this tree) | aura row never builds for the session | pcall + `diagnostics().error` shows it | §10.1 probe 9 |
| Resize denied while auras secret (F4) | low | mixed icon sizes until the next size change | pcall containment, no error | §10.2 step 7 |
| Offline harness cannot prove raise-on-comparison (M5/F9) | certain offline | scrub unproven offline | scrub kept; paint-boundary twins proven | restricted-state grey-face observations |
| TOC/release litter (`luac.out`, F2) | certain | none (not loaded) | not in the TOC | delete before release |

---

## 12. Attestation

- **Read-only on the product:** no file outside `bench/` and `desks/aura-hud-verify/` was
  written by this lane. All mutation/harness work happened in `/tmp` copies that were
  discarded inside the same shell call.
- **No git command** was run in `/home/sam/SwedgeTimer`. The only `git` use was read-only
  `git -C /home/sam/wow-ui-source show origin/forever:<path>` for the API citations.
- **No version, TOC, config, option, doc or lint-config change.**
- **Evidence freshness:** every number above was produced on the current tree
  (mtime set: 2026-11-08 21:49–22:16), after both lanes finished, not copied from their
  reports. Where a number matches a report, it was reproduced independently.
- **Judgement calls disclosed:** M5 accepted as a declared offline survivor (F9); F2/F3/F4
  are reported, not fixed; the pre-existing-check parity (§9.1) is count-based, not a byte
  diff (no VCS history is available to this lane).
