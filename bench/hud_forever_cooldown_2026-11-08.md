# HUD Forever secret-safe cooldown / GCD + cache hardening (2026-11-08)

- **Team / task:** `swedge-forever-hud` / t3, attempt 1
  (`979874ee-8826-4232-b937-1fd8ec9b7cb4`). Implementer lane.
- **Files written (exact scope):** `hud.lua`, `compat.lua` (additive helpers only),
  `LibGlobalCooldown.lua`, `tests/hud_state.lua`, `tests/forever_secret_compat_state.lua`,
  this report, `desks/hud-cooldown-fix/**`. **No** git operation, version field, TOC,
  config/options, `main.lua`, `bars.lua`, class module or docs edit. LF only.
- **Contract used:** `bench/forever_hud_api_2026-11-08.md` (T1; `origin/forever`
  `eac30af59`, 1.60.1 (70790)) plus `bench/briefs/brief_hud_cooldown_impl_2026-11-08.md`.
- **Hard gate honoured everywhere:** every new branch is
  `st.family == "FOREVER"` **and** an exact API probe
  (`api.get_spell_cooldown_duration` / `api.spell_cooldown_state` /
  `api.create_duration_text_binding` exists and answers). Never `st.is_mainline` alone.
  On every other client the helper answers nil and the existing numeric code runs
  unchanged (pinned by tests and by mutant M8).

## 0. Verdict

On WoW Forever, while the client hides cooldown timing (combat, encounter, challenge
mode, PvP), the HUD now paints **real native cooldown swipes and countdowns** through the
sanctioned opaque `LuaDurationObject` pass-through, and the GCD rides the same object on
the active ability icons. No secret value is read, compared, formatted, concatenated or
stored anywhere in the HUD, `compat` or `LibGlobalCooldown`; a secret that nevertheless
reaches a cache or a provider state is dropped at the boundary and lands on the documented
unknown face (grey, no swipe, no text). Every other client takes the byte-identical
numeric path. The old conclusion that "a swipe cannot be driven from a restricted read"
(`bench/secret_api_matrix_2026-11-06.md:156`) is superseded exactly as T1 proved.

## 1. What changed, file by file

### `compat.lua` (additive; no existing wrapper contract changed)

Captured Forever surfaces next to the existing cooldown locals (`:359-366`):
`C_Secrets.ShouldSpellCooldownBeSecret`, `C_DurationUtil.CreateDurationTextBinding`,
`C_StringUtil.CreateSecondsFormatter`, `C_CurveUtil.CreateColorCurve` — all read with
`rawget(_G, …)` so a client without them is inert.

New helpers (`:559-737`, above the unchanged `api.GetSpellCooldown` /
`api.get_cooldown_remaining`):

| Helper | line | contract |
|---|---|---|
| `api.get_spell_cooldown_duration(spell, ignore_gcd)` | `:575` | Forever-only + probe-gated. Returns the **opaque `LuaDurationObject`** plus its own `HasSecretValues()` answer (plain bool; `nil` when the probe is absent). `ignore_gcd == true` forwarded, default false (GCD included). Declines (nil) on a non-Forever family, invalid token, throwing reader/probe, or a secret probe answer. **Never reads a duration value.** |
| `api.get_spell_cooldown_state(spell)` | `:602` | Forever-only. Returns the two `NeverSecret` `SpellCooldownInfo` fields as exact booleans: `isOnGCD`, `isActive` (`SpellSharedDocumentation.lua:25,26,30`). `nil, nil` when the client cannot answer or a field is secret (nothing is compared). |
| `api.get_spell_cooldown_secrecy(spell)` | `:625` | Forever-only. `C_Secrets.ShouldSpellCooldownBeSecret` as a plain boolean or nil. Used as the last authority in `HUD.paint`. |
| `api.create_duration_text_binding()` | `:643` | Forever-only. `C_DurationUtil.CreateDurationTextBinding`, pcall-guarded. |
| `api.create_seconds_formatter()` | `:659` | Forever-only. Formatter configured with **plain arguments only** (abbreviation None, min/max interval Seconds, Truncate, one unit, round-up last unit, ms threshold 3 s); every setter pcall-guarded so an older build still yields a formatter. |
| `api.create_duration_text_color_curve(warn_seconds, warn, normal)` | `:694` | Forever-only. Step colour curve + `Enum.DurationTextBindingProperty.RemainingDuration`; the binding evaluates it against the secret remaining duration natively. Colours are validated plain 0-1 `colorRGBA` tables. |

### `hud.lua`

**Forever native pass-through** (new block `:1370-1503`, just above `HUD.paint`):

- `HUD.cooldown_spell(icon)` `:1382` — the slot descriptor's `cooldown_spell` override,
  else `slot.spell`; **nil for trinket slots** (no item duration-object API exists — T1 §7).
- `forever_native_enabled()` `:1399` — `st.family == "FOREVER"` **and**
  `type(api.get_spell_cooldown_duration) == "function"`.
- `acquire_cooldown_object(icon)` `:1407` — pcall the reader with `ignore_gcd = false`
  (the GCD must ride the object), then `api.get_spell_cooldown_state` for the two plain
  fields. Returns `(object, on_gcd, active)`.
- `prepare_text_binding(icon)` `:1428` — lazily builds the native binding for the icon's
  existing `icon.text` FontString (`SetFontString`, `SetFormatter`, `SetUpdateInterval`,
  `SetZeroDurationText("")`, `SetExpiredText("")`); failure is latched and costs only the
  text, never the swipe.
- `update_text_color_curve(self, icon, db, binding)` `:1470` — builds the warn-colour curve
  from the db colours (0-255 → 0-1 via `self:convert_color`) and rebuilds only when the
  db colours change.
- `release_text_binding(icon)` `:1497` — `Disable()` + drop the numeric text cache so the
  numeric path re-applies its own string and colour when the restricted window ends.

**`HUD.paint` rewrite** (`:1506-1780`, numeric visuals preserved line-for-line):

1. `:1506-1536` — SEC-13 header. Every field is probed with `api.is_secret` **before** any
   branch: a secret `hidden` degrades to "draw nothing"; a secret `restricted` or any
   secret numeric timing (`remaining`/`duration`/`text_remaining`/`start`) sets
   `restricted = true`; secret boolean cues (`usable`, `in_range`, `glow`, `desaturate`,
   `reverse`) resolve to the unknown/no-cue face — they never reach `== false`.
2. `:1543-1552` — the client's own `ShouldSpellCooldownBeSecret` is consulted when the
   provider did not flag the slot; a plain `true` forces the restricted face. This is the
   safety net against a stale numeric provider face (mutant M9).
3. `:1554-1592` — **object mode**: while restricted, acquire the handle and hand it to
   `icon.cooldown:SetCooldownFromDurationObject(object, true)` under pcall. `clearIfZero`
   clears an ended cooldown/GCD. The external-addon suppression flags are re-asserted
   exactly like the numeric path; `icon.cd_object` stores the **handle**, never a number.
   An engine refusal (U3 runtime) falls back to the existing grey unknown face.
4. `:1593-1604` — texture (a secret texture is dropped to the default).
5. `:1605-1650` — swipe. Object mode skips the numeric branch; otherwise the existing
   set-once numeric `SetCooldown` sequence is unchanged (including the clear branch).
6. `:1651-1736` — countdown text. Object mode feeds the native binding
   (`SetDuration(object)` + `SetEnabled(true)`); the **2 s GCD rule** is applied from the
   plain `isOnGCD` field (`SetEnabled` suppressed + text hidden while on the GCD). The
   numeric branch is byte-identical to before.
7. `:1737-1780` — desaturate/tints/glow. Object mode greys from the plain
   `on_gcd`/`active` fields; the `unknown_face` (restricted **and** no object) keeps the
   old grey face; the boolean-cue guards above are honoured.

**SEC-13 state scrub** (`:1837-1878`, called from `HUD.update_display` `:1943`): before any
per-frame branch reads the provider state, a fixed field list is scanned; when anything is
secret the reused `SAFE_STATE` table is filled with **only** plain fields (secret numeric
timing → `restricted = true`; secret cue → nil; secret `hidden` → hidden). No secret is
ever copied. Nothing-secret returns the provider table itself (zero allocation, exact no-op
on every client without secret values).

**Cache hardening** (the operator's specific worry):

- `hud_known_query` `:954-1002`: a secret spell id is refused before it can be a cache key
  or a client query (Blizzard's own "secret keys poison the table" rule); a cached name
  that is secret is dropped; a secret `GetSpellInfo` name is never written
  (`HUD.known_names` write sites `:979`, `:985`).
- `known_cache` (exposed as `HUD.known_cache` `:1049` for audit/tests):
  `HUD.spell_known_allows` `:1057-1095` re-proves a cached entry (`type` + `is_secret` on
  `at`/`value`) before reading it, drops a poisoned entry, never caches a secret answer or
  a secret clock, and only writes plain numbers/booleans.
- Trinkets: `trinket_record_is_poisoned` `:292`, `HUD.read_trinket` `:301`,
  `scan_trinket_proc` `:332`, `trinket_has_on_use` `:372`, `HUD.trinket_usable` `:394`,
  `HUD.on_aura_applied` `:424`, `HUD.trinket_state` `:461-545` — a poisoned record is
  dropped before any field is compared; every read is re-proved plain before it can reach
  the tracker, the arithmetic or the 1.5 s GCD filter. SEC-10's tri-state is unchanged.
- `icon.cd_object` / `icon.text_binding` / `icon.text_binding_owned` / `icon.text_curve_key`
  (fields created `:647-663`): plain bools and non-secret handles only.

### `LibGlobalCooldown.lua`

- `plain_number(value)` `:53` — `is_secret` probed **before** `type()`/comparisons; a
  restricted or non-finite value is nil.
- New callback names `:91` `GCD_OBJECT_STARTED` / `GCD_OBJECT_OVER`; new state
  `:106` `lib.gcd_object` / `lib.gcd_on_gcd` (the opaque handle + the plain NeverSecret
  GCD field; **no number is derived from the object**).
- `clear_gcd_object()` `:184` — clears the channel, fires the over event once.
- `poll_gcd()` `:193` — Forever-only + probe-gated first: when the plain `isOnGCD`/`isActive`
  say a GCD is running, store the handle and fire `GCD_OBJECT_STARTED` on the transition;
  when they say it ended, clear + fire `GCD_OBJECT_OVER`. Then the original numeric path,
  with two safety changes: the 5th `restricted` return clears the timing state instead of
  storing a partial number from the degraded idle shape; and a readable idle read releases
  a stale object channel.
- `release_gcd_lock()` `:175` — also clears the object channel.
- `UNIT_SPELLCAST_INTERRUPTED` `:318` — **kept exactly as pinned** by
  `tests/secret_guard_state.lua` (see §6 deviation 2).

### `tests/`

- `tests/hud_state.lua`: fixtures extended (C_Spell / C_Secrets / C_DurationUtil /
  C_StringUtil / C_CurveUtil / C_Timer / LibStub `NewLibrary` + CallbackHandler; the frame
  stub records `SetCooldownFromDurationObject`); new sections **23-28** (`:3412-3858`):
  Forever restricted ability cooldown, Forever plain cooldown, Forever GCD + GCD end,
  non-Forever byte-identical path, missing-API faces, cache hygiene, poisoned provider
  state, LibGlobalCooldown object channel + restricted cache rule. **1 024 checks**
  (was 893 → +131).
- `tests/forever_secret_compat_state.lua`: new sections **8-11** (`:856-1059`):
  duration-object reader, NeverSecret state fields, secrecy predicate, native text binding /
  formatter / colour curve. **250 checks** (was 177 → +73).

## 2. The exact Forever path chosen

```
provider state (forever_guide.get_hud_state)  -- unchanged; flags restricted, numbers 0
        │
        ▼
HUD.paint:
  restricted?  (provider flag, secret-field re-check, or C_Secrets.ShouldSpellCooldownBeSecret)
        │ yes
        ▼
  C_Spell.GetSpellCooldownDuration(slot spell, ignoreGCD=false)   ← compat :575
        │  returns opaque LuaDurationObject (non-secret handle; its values may be secret)
        ▼
  CooldownFrame:SetCooldownFromDurationObject(object, true)        ← hud :1565
        │  native swipe, clearIfZero; no Lua number read
        ├── C_Spell.GetSpellCooldown(spell).isOnGCD / .isActive    ← compat :602 (plain bools)
        │      → desaturate decision + the 2 s GCD text rule
        ▼
  C_DurationUtil.CreateDurationTextBinding()                        ← compat :643
  binding:SetFontString(icon.text) / SetFormatter(seconds formatter) / SetUpdateInterval(0.05)
  binding:SetTextColorCurve(warn curve, RemainingDuration)          ← compat :659/:694
  binding:SetDuration(object); binding:SetEnabled(true)             ← hud :1666
        │  the client formats + colours; `GetText`/`GetFormattedText` never read
        ▼
  cache rule: icon.cd_object = the HANDLE only; text_value = nil (binding owns the text);
              no numeric timing from the object enters any table, comparison, formatter or key
```

T1 citations used: `SpellDocumentation.lua:326-343` (no `SecretWhen*` on
`GetSpellCooldownDuration`), `FrameAPICooldownDocumentation.lua:307-318` (no
`SecretArgumentsAddAspect` on the object sink), `UnitFrame/Shared/UnitFrameUtil.lua:487`
(`AllowedWhenUntainted` refuses secret *arguments* only), `LuaDurationObjectAPIDocumentation
.lua:350-364` (`HasSecretValues` ReturnsNeverSecret), `SpellSharedDocumentation.lua:25,26,30`
(`isEnabled`/`isActive`/`isOnGCD` NeverSecret), `DurationUtilDocumentation.lua:20-29`,
`DurationTextBindingObjectAPIDocumentation.lua:249-259,282-292,293-303,304-315`,
`SecondsFormatterAPIDocumentation.lua:362-461`, `CurveUtilDocumentation.lua:10-19`,
`DurationTextBindingSharedDocumentation.lua:5-21`, `Blizzard_CustomAuraButton.lua:598-623`,
`Blizzard_AuraContainerShared.lua:74-98`, `CooldownViewer.lua:1013-1045`.

**Why object mode only while restricted.** In readable states the provider already carries
plain numbers, so the exact old numeric face (custom text, colours, 0.1 s precision,
set-once `SetCooldown`) runs untouched on **every** client, Forever included. That is the
boring, provable choice and it makes "every other client byte-identical" trivially true.
On each restricted tick the handle is re-acquired and re-fed to the sink so the native frame
always tracks the live cooldown regardless of whether the object is live-updating or a
snapshot (T1 U6 leaves that open) — the object is opaque, so re-feeding is the only correct
cadence.

## 3. Cache hazard matrix (before → after)

Legend: **plain** = provably a number/boolean/string from the guarded wrapper; **handle** =
non-secret opaque object; **drop** = refused/dropped before any compare.

| Cache | before | after |
|---|---|---|
| `HUD.known_names` (id → name) | write on `type(n)=="string"` only; a secret id or secret name would be written | **drop**: secret `slot.spell` returns no query (never a key, never a client query); a secret cached name is dropped on read; a secret `GetSpellInfo` name is never written (`hud.lua:954-1002`) |
| `known_cache` (slot → `{at,value}`, weak keys) | plain by construction, but a poisoned entry would be consumed for a full TTL | **drop + re-prove**: `type`+`is_secret` on `at`/`value` before read, poisoned entry deleted, secret answer/clock never written (`hud.lua:1047-1095`) |
| `HUD.layout_cache` | saved-variable values only | unchanged (no client read enters it; no frame-geometry read-backs added) |
| `HUD.icons[i].cd_start/cd_duration/cd_reverse/cd_key` | numbers only from compat's plain reads | unchanged for the numeric path; **object mode stores `icon.cd_object` (handle) and keeps the numeric fields nil** — never a derived start/duration |
| `HUD.icons[i].text_value/text_color/text_hidden` | derived plain values | unchanged; released/nil'd when the native binding owns the string, re-applied after |
| `HUD.icons[i].text_binding/text_curve_key` | — | new: a plain binding handle + the db colour tables the curve was built from (plain saved values) |
| `HUD.trinkets[13/14]` (`item,buff,icd,texture,icd_expires,proc_expires,proc_duration`) | guarded only through the compat wrappers; a poisoned field would be compared | **drop**: `trinket_record_is_poisoned` clears the record before any compare; aura/proc writes re-proved plain; the four item-cooldown returns re-proved plain before the 1.5 s filter (`hud.lua:292-545`) |
| `TRINKET_STATE` | reused plain table | unchanged + every numeric field re-proved at the tick boundary |
| `PREVIEW_STATE` | reused plain table; `restricted` never reset | `restricted = nil` added to both reset lists (`hud.lua:1791`, `:1957`) |
| `state` hand-off (provider → paint) | paint re-checked 4 numeric fields (SEC-12) | **SEC-13**: `scrub_secret_state` normalises the whole field set before `update_display`'s own branches; `paint` independently probes booleans + numerics before every comparison (`hud.lua:1506-1536`, `:1837-1878`) |
| `LibGlobalCooldown.gcd_duration/gcd_started/gcd_expires` | plain only because a restricted read answered zeros; a partial number could be stored | **clear/skip**: a restricted read clears instead of storing; `plain_number` refuses secret/non-finite values (`LibGlobalCooldown.lua:53,193-260`) |
| `LibGlobalCooldown.gcd_object/gcd_on_gcd` | — | new: handle + plain NeverSecret bool; **no expiry is computed from the object** |
| `current_spell_gcd/current_spell_haste/phys_gcd/...` | guarded haste reads, plain derivations | unchanged |

## 4. Test evidence

Commands run from the repo root (LF preserved; no config/lint changes):

| Command | Result |
|---|---|
| `bash tests/run.sh` (baseline before edits) | **58 steps, 0 failed** |
| `bash tests/run.sh` (final) | **59 steps, 0 failed** (58 suites + luacheck; the 59th step is the other lane's newly registered `aura_icons_state.lua`) |
| `lua5.1 tests/hud_state.lua` | **PASS — 1 024 checks, 0 failed** (baseline 893) |
| `lua5.1 tests/forever_secret_compat_state.lua` | **250 checks, 0 failed** (baseline 177) |
| `lua5.1 tests/secret_guard_state.lua` (cross-lane, unmodified) | **PASS — 524 checks, 0 failed** |
| `lua5.1 tests/forever_hud_gate_state.lua` | **PASS — 174 checks, 0 failed** |
| `luacheck .` | **2 warnings / 0 errors in 105 files** — the tree floor: both pre-existing in `hunter_ui.lua` (out of scope, untouched). My three modules and two test files are warning-free. |
| `luac5.1 -p` on every root/`classes` file (via run.sh) | PASS |
| `luac5.1 -p hud.lua compat.lua LibGlobalCooldown.lua tests/hud_state.lua tests/forever_secret_compat_state.lua` | all OK |
| local budget (`tests/toc_check.lua`) | hud.lua **59** locals densest prototype (limit 190, headroom 141); compat.lua 86 (headroom 114); LibGlobalCooldown.lua 23 (headroom 177); tightest tree file unchanged (warrior 188/200) |

Cross-lane note: during the first post-change harness run, `tests/toc_check.lua` failed
3 checks because the parallel t4 aura-row lane had just added `aura_icons.lua` +
`tests/aura_icons_state.lua` before registering them in the TOC/run.sh. That is **not** my
change (I touched no TOC/run.sh); the final harness run above is green after that lane
finished its registration.

## 5. Mutation table (revert-proof)

Method: fresh `mktemp` copy of the repo (`rsync -a --exclude=Media --exclude=docs
--exclude=.git`), **all three source files restored** before each mutant, one single-site
reversion applied, relevant suite run, copy deleted. Never mutated the real tree. Note for
future lanes: **a bash call here gets a private `/tmp`** — the copy, the mutant, the suite
and the cleanup must happen inside one call (T1 recorded the same trap).

| # | Mutant (single-site inversion) | Expected failure | Actual |
|---|---|---|---|
| M1 | `if restricted and forever_native_enabled()` → `if false and …` (object path removed) | Forever legs lose the sink/text | **34 / 1024 checks failed, exit 1** |
| M2 | `restricted = probe(s.restricted) and true or (s.restricted == true)` → `restricted = false` (restricted paints as readable) | the grey unknown face legs (SEC-10/SEC-12/new) | **41 / 1024, exit 1** |
| M3 | secret-id early return in `hud_known_query` disabled | `known_names` caches a secret key | **1 / 1024, exit 1** |
| M4 | `if not entry_ok then …` cache revalidation disabled | a later tick returns the poisoned cached value | **3 / 1024, exit 1** |
| M6 | Forever object-channel gate in `lib:poll_gcd` disabled | LGC stores no object / fires no event | **11 / 1024, exit 1** |
| M7 | SEC-12 numeric secret re-check removed from `paint` | a leaked secret numeric paints a fabricated swipe | **6 / 1024, exit 1** |
| M8 | `st.family ~= "FOREVER"` gate removed from `api.get_spell_cooldown_duration` | non-Forever legs must observe zero client calls | **4 / 250 compat checks, exit 1** (`hud_state` stays green — the HUD has its own family+probe gate: defence in depth) |
| M9 | `C_Secrets.ShouldSpellCooldownBeSecret` override disabled in `paint` | the secrecy-predicate leg | **2 / 1024, exit 1** |
| M5 | `s = scrub_secret_state(s)` → `s = (s)` (state scrub removed) | — | **0 failures, exit 0 — SURVIVES** |

**M5 explained (honest result):** the offline stub can flag ordinary Lua primitives
(`issecretvalue` returns a boolean for a sentinel table) but Lua 5.1 cannot make
`not s.hidden` or `a >= b` *raise* on a flagged number/string. In the stub, a secret `hidden`
is still truthy, so `update_display` hides it either way and the tick does not die — the
scrub is therefore redundant **offline**. It is kept because on the real client the scrub is
the only guard for `update_display`'s own branches (which `paint` never sees), and its
paint-boundary twins are proven to bite (M2/M7). No test was written that pretends to prove
it; the in-client probes below are how it gets closed.

## 6. Deviations from the brief / corrections to T1 (reported, not silent)

1. **T1 §7 trinket fourth-return claim does not apply to this tree.** T1 says
   `compat.lua` reads the client's fourth `GetInventoryItemCooldown` value as `restricted`.
   It does not: `compat.lua:1760` reads **three** values and the fourth return is
   compat's own SEC-10 flag (`0,0,0,true` only when a raw value is secret). The client's
   `isOnGCD` fourth value is simply dropped, which is harmless here because the HUD's
   on-use filter already requires `duration > 1.5` (a GCD is ≤ 1.5 s). Changing the
   wrapper's arity is forbidden by this brief ("additive helpers only; do not change an
   existing wrapper contract") and the HUD needs no fifth value, so no change was made;
   the documented four-value shape is recorded for the next contract revision. Item
   cooldowns carry no `SecretWhen*` predicate, so the SEC-10 grey face stays the correct
   face for the hypothetical restricted item read — preserved and re-pinned.
2. **`UNIT_SPELLCAST_INTERRUPTED` keeps releasing on a restricted read.**
   `tests/secret_guard_state.lua` is cross-lane and pins "a secret reading releases the
   lock" (`:638-643`). My first version returned early on `restricted == true` and failed
   that pin; restored to the historical shape. The object channel is released from the
   plain GCD state instead, so the T1 warning ("must not become the only release path") is
   honoured without re-cutting a cross-lane pin.
3. **GCD wiring split.** The HUD paints the GCD from its own per-spell object
   (`ignoreGCD = false`) — the T1 primary candidate — because that is the only wiring that
   can reach a HUD icon without touching `main.lua` (out of scope). `LibGlobalCooldown`
   additionally exposes the additive `GCD_OBJECT_STARTED`/`GCD_OBJECT_OVER` channel and
   stops caching a restricted partial; `main.lua` is untouched, so `ST.gcd` keeps its
   historical numeric semantics and no consumer changes behaviour.
4. **Restricted text face is native formatting.** Formatter configuration matches the
   readable face as closely as plain arguments allow (bare numbers, 3 s decimal threshold,
   one unit, Truncate + round-up last unit = Blizzard's own aura formatter). Rounding can
   differ from the readable `format_time` by at most 1 s and the 0.1 s precision rule only
   applies below 3 s; the old rule "hide text for cooldowns whose **total** < 2 s" cannot be
   expressed without reading the object's total, so only the **GCD** case (the rule the
   brief names) is enforced — via the plain `isOnGCD` field. When the state fields are
   unanswerable the binding still shows native text rather than hiding a real countdown.
5. **Object re-fed every restricted tick** (not set-once): the object is opaque, so the
   HUD cannot tell whether a new object carries new values; re-feeding is the only correct
   cadence and costs native calls only in restricted moments.

## 7. UNCONFIRMED in-client items (close with these exact probes)

All are inherited runtime facts from T1 §11; nothing in this change can answer them offline.
Run them in a Forever dungeon pull (combat + restricted), with `/st diag` printed in the
same session so each line is attributable.

| # | Probe (`/run …`) | What it closes |
|---|---|---|
| P3 | `/run local d=C_Spell.GetSpellCooldownDuration(61304,false) local i=C_Spell.GetSpellCooldown(61304) print(type(d), issecretvalue(d), d:HasSecretValues(), i and i.isOnGCD, i and i.isActive)` during a GCD, then idle | U6, U7 — that the per-spell object carries the GCD, and the probe spell's secrecy |
| P4 | `/run local c=CreateFrame("Cooldown",nil,UIParent,"CooldownFrameTemplate") local d=C_Spell.GetSpellCooldownDuration(20271,false) print(pcall(function() c:SetCooldownFromDurationObject(d,true) end))` — restricted combat, then move the frame on screen | U3 — the engine accepts a secret-valued object from a tainted caller (the pcall fallback is the grey face) |
| P5 | `/run local b=C_DurationUtil.CreateDurationTextBinding() local f=UIParent:CreateFontString(nil,"OVERLAY") f:SetPoint("CENTER") b:SetFontString(f) b:SetFormatter(C_StringUtil.CreateSecondsFormatter()) b:SetUpdateInterval(0.05) b:SetDuration(C_Spell.GetSpellCooldownDuration(20271,false)) b:Enable() print(b:HasSecretValues(), pcall(b.GetFormattedText,b))` | U3/U5 — the binding renders a countdown for a secret-valued object, and whether `GetFormattedText` is secret (it must never be called by addon code) |
| P6 | `/run local d=C_Spell.GetSpellCooldownDuration(20271,false) print(d:HasSecretValues(), pcall(d.GetRemainingDuration,d), issecretvalue((select(2,pcall(d.GetRemainingDuration,d)))))` | U4 — confirms the design assumption that object getters are unusable in Lua (we never call them) |
| P7 | `/run local c=CreateFrame("Cooldown",nil,UIParent,"CooldownFrameTemplate") c:SetSize(64,64) c:SetPoint("CENTER") c:SetHideCountdownNumbers(false) c:SetCountdownFormatter(C_StringUtil.CreateSecondsFormatter()) local d=C_Spell.GetSpellCooldownDuration(20271,false) print(pcall(function() c:SetCooldownFromDurationObject(d,false) end))` | U5 — native frame numbers for a secret duration (we keep them hidden; this is the double-check) |
| P8 | `/run local a,b,c,e=GetInventoryItemCooldown("player",13) print(a,b,c,type(e),tostring(e))` idle then right after pressing the trinket | U10/U11 — the client's fourth return is `isOnGCD`, and items stay readable (SEC-10 grey face otherwise) |
| P10 | `/run print(C_Secrets.GetSpellCooldownSecrecy(20271), C_Secrets.ShouldSpellCooldownBeSecret(20271))` in and out of combat | U1/U9 — the latest-authority predicate that now forces the object path in `paint` |

What the operator should see once P4/P5 confirm U3/U5: on a dungeon pull with cooldowns
running, ability icons show real swipes and countdowns, the GCD sweeps the row, trinkets
stay as they were (numeric swipe; grey only if the client hides item timing), and no
BugSack/taint error appears when a cooldown starts or ends in combat.

## 8. Attestation

- Only the five in-scope files were modified (verified with `git status --porcelain` on the
  exact paths); no other product file, test, TOC, config, options, `main.lua`, `bars.lua`,
  class module, doc or git state was touched. `tests/secret_guard_state.lua` was run but
  **not** modified (cross-lane).
- LF only, no line-ending churn; no lint-config change; no `_` silencing; every new warning
  wiring is a real guard with a written reason.
- All new tests were run against an isolated mutated copy for the reverse proof (§5), never
  against the real tree.
