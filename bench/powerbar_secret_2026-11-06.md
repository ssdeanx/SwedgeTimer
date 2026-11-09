# Power bar blocked by secret power reads on WoW Forever — root cause + fix

- **Desk:** `powerbar-fix` (writer)
- **Date:** 2026-11-06
- **Operator report (verbatim):** primary power bar does not show on WoW Forever —
  "power bar is being blocked becuz its secret ... i'm pretty sure u need to pass the
  secret data through for it to work."
- **Verdict:** CONFIRMED and fixed offline. A restricted `UnitPower`/`UnitPowerMax` read
  used to turn into `nil` in `compat.lua` (right for arithmetic consumers) and the bar
  then hid with `why=no-value`. The bar now paints that value through a real `StatusBar`
  (`SetMinMaxValues` + `SetValue`, both documented `AllowedWhenTainted` with the
  `BarValue` secret aspect) and never compares/formats the opaque value. In-client
  behaviour is UNVERIFIED (see §7); the client is the only place a real secret exists.

**Files changed (all in this desk's scope):**

| File | Change |
|---|---|
| `compat.lua` | additive `api.GetPlayerPower(power_type)` → `value, max_value, restricted` (raw readings, never nil'd; flag = `is_secret(value) or is_secret(max_value)`, `false` on classic clients). `api.UnitPower`/`api.UnitPowerMax` keep the exact nil-on-secret contract. `api.UnitPowerType` untouched. |
| `power_bar.lua` | the fill is a real `CreateFrame("StatusBar", ...)` (track inset preserved) painted via `SetMinMaxValues(0,max)` + `SetValue(value)` + `SetStatusBarColor`; a restricted read is painted raw with `fraction`/text formatting skipped (label `"?"`, or hidden when the text option is off); `pb.resolve`/`pb.last_state`/`pb.update` carry and honour `restricted`. |
| `diag.lua` | verbose power line reads the raw reader; a restricted read renders `value=restricted fraction=?` and is never `tostring`'d or divided; the old `UnitPower`/`UnitPowerMax` fallback path is unchanged. |
| `tests/power_bar_state.lua` | StatusBar sandbox (methods + call log), rewritten fill/pixel pins, new §12 restricted + non-restricted contract. 220 checks. |
| `tests/forever_secret_compat_state.lua` | new §7 raw-reader contract (modern readable, secret value, secret max, both, classic, no `issecretvalue`, missing max, absent API, and the preserved nil-on-secret pair). 170 checks. |
| `desks/powerbar-fix/**` | journal, done signal, `run_mutations.sh` (mutation proof harness). |

No TOC/`run.sh` change was needed — both suites were already registered
(`tests/run.sh:103`, `tests/run.sh:105`).

## 1. Root cause (verified on `origin/forever`)

1. **The reads are secret-restricted.** `UnitPower` carries
   `SecretWhenUnitPowerRestricted = true`
   (`origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:2732-2747`;
   declaration at `:2734`), and `UnitPowerMax` carries
   `SecretWhenUnitPowerMaxRestricted = true` (`:2801-2824`; declaration at `:2803`).
   `UnitPowerPercent`/`UnitPowerMissing` are restricted the same way. `UnitPowerType` is
   **not** secret (`:2859-2878`, only `MayReturnNothing`), so the power TYPE can always be
   read and the bar can still pick its colour.
2. **A StatusBar is the sanctioned sink for a secret value.**
   `StatusBar:SetMinMaxValues` is `SecretArguments = "AllowedWhenTainted"` with
   `SecretArgumentsAddAspect = { Enum.SecretAspect.BarValue }`
   (`SimpleStatusBarAPIDocumentation.lua:229-236`), and `SetValue` is the same
   (`:354-361`). `SetStatusBarColor` is also `AllowedWhenTainted` (`:282-292`), and
   `SetStatusBarTexture` exists (`:318-326`).
3. **Blizzard does exactly this.** `UnitFrameManaBar_Update` passes the raw reads with no
   Lua arithmetic: `local maxValue = UnitPowerMax(unit, statusbar.powerType)` →
   `statusbar:SetMinMaxValues(0, maxValue)` → `local currValue = UnitPower(unit, ...)` →
   `statusbar:SetValue(currValue)`
   (`origin/forever:Interface/AddOns/Blizzard_UnitFrame/Mainline/UnitFrame.lua:943-975`;
   the calls are at `:948`, `:950`, `:962`, `:970`).
4. **The shipped defect.** `compat.lua`'s `api.UnitPower`/`api.UnitPowerMax` return `nil`
   for a secret value (the correct contract for the 10+ arithmetic consumers in
   `classes/*.lua`), and the old `power_bar.lua` required numbers in `pb.resolve`, then
   computed a fill width with `pb.fraction` and `texture:SetWidth`. A restricted read
   therefore resolved to `why=no-value` (or `no-type` when the token was secret) and the
   bar was hidden — silently, because every hide path in the module is silent by design.
   That is the operator's symptom.
5. **Supporting secrecy API (not needed by this fix, recorded for the next reader).**
   `C_Secrets.GetPowerTypeSecrecy(powerType)` returns a `SecrecyLevel`
   (`SecretPredicateAPIDocumentation.lua:29-41`); the enum is
   `NeverSecret = 0, AlwaysSecret = 1, ContextuallySecret = 2`
   (`SecretWrapperConstantsDocumentation.lua:6-15`). The bar does not need to ask: the
   `restricted` flag from `api.GetPlayerPower` is the per-read truth, and `GetPowerTypeSecrecy`
   is a base-class hint, not evidence about this tick.

## 2. The fix

### compat.lua — one additive reader, existing contracts untouched

`api.GetPlayerPower(power_type)` (`compat.lua:626-651`) returns the **raw** client
readings and a flag:

```lua
api.GetPlayerPower = function(power_type)
    if not legacy_unit_power then return nil, nil, false end
    local value = legacy_unit_power("player", power_type)
    if not legacy_unit_power_max then return value, nil, is_secret(value) end
    local max_value = legacy_unit_power_max("player", power_type)
    return value, max_value, is_secret(value) or is_secret(max_value)
end
```

- The comment cites the Forever docs (UnitDocumentation, SimpleStatusBar, Blizzard's
  mana bar) so the next reader sees WHY the additive reader exists next to the nil'ing
  pair.
- `restricted` is `false` (never `nil`) when nothing is secret, including on every
  classic client: `issecretvalue` is absent there, so `is_secret` is the local
  `function() return false end` — no value can ever be flagged.
- `api.UnitPower`/`api.UnitPowerMax` are **byte-identical** in behaviour: still `nil` on a
  secret, still `0` when the client has no `UnitPower` at all. Every arithmetic consumer
  (`classes/*.lua` resource gates) keeps its "unknown" branch.

### power_bar.lua — the fill is a real StatusBar

- `pb.init` creates `CreateFrame("StatusBar", addon_name .. "PowerBarFill", frame)`
  (`power_bar.lua:623`), sets the flat white statusbar texture
  (`Interface\\Buttons\\WHITE8X8`, LibSharedMedia's canonical "Solid" statusbar asset),
  the power colour, and a sane pre-paint range. The outer `pb.frame` keeps the background
  texture, the geometry, the anchoring and the driver/event frames. The value font string
  is parented to the StatusBar (a child frame always draws above its parent's own regions;
  a font string on the container would sit behind the track) — `power_bar.lua:634-647`.
- `pb.fill_dimensions(width, height)` (`:199-215`) subtracts the old 1 px inset and clamps,
  and `layout` sizes the track from it (`:341-352`). With a 275 px owning bar the track is
  273 x 12, so the widget paints `fraction * 273` — the exact pixel width the old
  hand-computed `SetWidth` produced (see §3).
- `pb.paint` (`:382-434`) hands a readable state to `SetMinMaxValues(0, max)`/`SetValue(value)`
  and a **restricted** state the raw pair, every restricted tick, with no comparison:
  ```lua
  frame.fill:SetMinMaxValues(0, state.max_value)
  frame.fill:SetValue(state.value)
  ```
  The colour is a constant palette value keyed by the (non-secret) power type. The label
  is `"?"` while restricted (constant — never formatted), or hidden when
  `power_bar_text_enabled == false`.
- `pb.resolve` (`:444-508`): requires `api.UnitPowerType` + `api.GetPlayerPower`; a
  restricted read may only use `type()` (safe on a secret) and then returns
  `restricted = true`, the raw values and `why = nil` — i.e. a PAINTED state. The readable
  path is unchanged (`type` checks, `max_value <= 0`, `pb.fraction`, `state.fraction`).
  `pb.update` therefore shows the bar (`:513-529`); only genuinely unknown reads hide.
- Hide paths keep the first meaningful token (`no-frame` / `no-addon` / `off` /
  `no-anchor` / `no-api` / `no-type` / `no-value` / `no-fraction`), so the diag line still
  attributes a hidden bar.

### diag.lua — read the raw reader, never format a secret

`power_live_text` (`diag.lua:822-893`) now prefers `api.GetPlayerPower`; when the flag is
exactly `true` it returns `type, token, "restricted", "?"` **before** any `tostring`,
comparison or fraction (`:845-856`). With no raw reader it falls back to the old
`UnitPower`/`UnitPowerMax` pair, so every existing fixture and every older client shape
prints exactly the same line as before. The line format is untouched (no new fields), so
`tests/diag_state.lua`'s exact-string pins stay valid.

## 3. Appearance contract proof (pixels and values)

The old fill painted `pb.fraction(value, max) * (width - 2)` px. The new track is
`width - 2` px and the StatusBar paints `(value - 0) / (max - 0)` of it, so the painted
width is identical; the test computes it from the recorded widget call
(`tests/power_bar_state.lua`: `painted_width`):

| Case | Old `fill:SetWidth` | New `painted_width(track)` |
|---|---|---|
| 3000/3000 @ 275 px | 273 | 273 |
| 1500/3000 @ 275 px | 136.5 | 136.5 |
| full @ 300 px | 298 | 298 |
| text 3000/1500/55 | `"3000"`/`"1500"`/`"55"` | same (`pb.format_value` unchanged) |
| mana/rage/energy/focus colours | palette entry | same palette via `SetStatusBarColor` |
| track geometry 14 px default / 20 px option | fill 12/18 px | track 12/18 px |

One deliberate, documented difference: at fraction 0 the old code forced a 1 px fill
sliver (`if fill_width < 1 then fill_width = 1 end`); a StatusBar at value 0 paints an
empty track. That is not a contract (it was a cosmetic floor) and no test asserted it.

## 4. Evidence

### Red first (new tests against the unmodified tree)

- `lua5.1 tests/power_bar_state.lua` → `FAIL` on: fill-dimensions helper absent, fill not
  a StatusBar, no raw read (`got 0, want 1`), falls back to the nil-on-secret pair
  (`got 2, want 0`), track min/max/value absent, full-width paint absent, then an abort
  on the missing StatusBar colour. (Old code hid the bar for a restricted read — the
  defect.)
- `lua5.1 tests/forever_secret_compat_state.lua` → `FAIL compat defines the raw
  secret-safe reader (api.GetPlayerPower)` (132 checks, 1 failed).

### Green (final tree, this desk's files)

- `lua5.1 tests/power_bar_state.lua` → `PASS power_bar_state.lua (220 checks)`, exit 0.
- `lua5.1 tests/forever_secret_compat_state.lua` → `170 checks, 0 failed`, exit 0.
- `luacheck compat.lua power_bar.lua diag.lua tests/power_bar_state.lua
  tests/forever_secret_compat_state.lua` → `0 warnings / 0 errors`.
- Whole-tree luacheck floor unchanged: `2 warnings / 0 errors in 100 files` (both
  pre-existing KEEP-ruled, not in this desk's files).
- LF preserved in every touched file (CRLF count 0); no lint-config change; no `_`
  silencing.
- diag restricted rendering (ad-hoc, not committed — see §6): opaque sentinels whose
  `__tostring`/`__lt`/`__le`/`__div`/`__mul`/`__unm` raise. The line rendered
  `type=0 token=MANA value=restricted fraction=? why=-` and did not throw; readable and
  fallback outputs were byte-identical to the old format. 6/6 checks.

### Mutation proofs (`bash desks/powerbar-fix/run_mutations.sh`, isolated `/tmp` copies)

Baseline first: the pristine copy passes both suites. Then every mutation must fail its
suite (non-zero exit + FAIL lines):

| # | Mutation | Suite | Result |
|---|---|---|---|
| M1 | `GetPlayerPower` nils a restricted value again (the original defect) | compat | **KILLED**, exit 1, 6 fails ("passed through raw, never nil'd") |
| M2 | compute a fraction (arithmetic) in the restricted resolve branch | power_bar | **KILLED**, exit 1, 2 fails ("nothing computes a fraction from a restricted value") |
| M2b | compare a restricted value (`max_value <= 0` guard) | power_bar | **KILLED**, exit 1, 5 fails (bar hidden for an opaque max) |
| M3 | hide instead of show on a restricted read | power_bar | **KILLED**, exit 1, 5 fails ("STILL SHOWS the bar") |
| M4 | format the restricted value into the label | power_bar | **KILLED**, exit 1, 3 fails ("renders a constant ? instead of the secret") |
| M5 | `api.UnitPower` stops nil'ing the secret (arithmetic contract weakened) | compat | **KILLED**, exit 1, 1 fail ("still reports nil on a secret") |

`6/6 mutations killed`. The script lives at `desks/powerbar-fix/run_mutations.sh`
(`SRC=` overrides the repo), so the proof is reproducible.

### Full harness (`bash tests/run.sh`) and crossfire

The tree is being edited concurrently by the Forever display/perf desks
(`main.lua`, `swing_source.lua`, `utils.lua`, `hunter_state`/`main_init_state`/
`engine_matrix_state`/`wiring_check` pins). Snapshot **2026-11-06 14:31:40**:

`57 steps, 4 failed` — failures: `hunter_state`, `main_init_state`,
`engine_matrix_state`, `wiring_check`. **None is this desk's file**, and this desk's
harness steps all pass in the same run: `diag_state`, `secret_guard_state`,
`forever_secret_compat_state`, `power_bar_state`, `toc_check`, and the luacheck step
(`2 warnings / 0 errors in 100 files`).

Crossfire attribution evidence:

- `main_init_state` fails on `A-2: the visibility pass runs even when the alpha pass
  throws (got 1, want 2)` — `main.lua` heartbeat counts (display/perf lane; `main.lua`
  mtime 14:31:00).
- `engine_matrix_state` fails on `forever payload: a zero/non-numeric duration is
  ignored` — the `swing_source.lua` forever-payload fallback (mtime 14:27:22), pins not
  yet reconciled.
- `wiring_check` exits 1 only on `stale ACCEPTED entry ... 3|main.lua|swing_timer_start-no-guard`
  and `...swing_timer_update-no-guard` — the display lane added the guards, so the
  accepted-defect entries are now stale (905 checks, 0 failures).
- `hunter_state` — hunter display lane.
- **A/B control:** in a copy of the tree with the additive `api.GetPlayerPower` block
  *removed*, `main_init_state` (`1 of 1068`, same A-2 check) and `engine_matrix_state`
  (`2 of 101`, same forever-payload checks) fail **identically**; `swing_source_state`
  passed in both copies. So no current harness red is caused by this fix.
- Earlier in the window `swing_source_state` was red (15 fails) while the display lane
  was mid-write; it went green in the same tree minutes later without any change here.
- **Later snapshot 2026-11-06 14:38:23:** `57 steps, 3 failed` — `hunter_state`,
  `engine_matrix_state`, `wiring_check` (`main_init_state` went green as the other lane
  reconciled its own pin). Same attribution; this desk's steps and the luacheck floor are
  unchanged (all PASS, `2 warnings / 0 errors in 100 files`).

## 5. Follow-ups (filed, not silently dropped)

1. **`tests/diag_state.lua` restricted pin** — the diag restricted rendering is proven by
   an ad-hoc script only because `tests/diag_state.lua` is outside this desk's write
   scope. The owner of that file should add a case:
   `st.api.GetPlayerPower = function() return secret, secret, true end` → the power line
   must contain `value=restricted fraction=?` and must not throw. The module itself is
   ready for that pin.
2. **Crossfire reconciliation (Lead):** `main_init_state` A-2, `engine_matrix_state`
   forever payload, `wiring_check` stale `main.lua` accept entries, `hunter_state` — all
   belong to the display/perf lanes and must be reconciled before the wave closes.
3. **In-client check (operator):** see §7.

## 6. Scope note

`diag_state.lua`'s restricted pin is the only intended test gap; it is filed above rather
than edited because the desk's write scope is exact. The ad-hoc script was run from
`/tmp` and deleted; it is not a committed artifact.

## 7. UNVERIFIED — needs the client

Offline stubs cannot create a real secret, so these are explicitly not claimed:

- **The real secret surface on Forever.** That a restricted `UnitPower`/`UnitPowerMax`
  read is opaque enough to raise on arithmetic/formatting, and that `issecretvalue`
  returns `true` for it in combat, is taken from the origin/forever documentation and
  Blizzard's own usage — not observed in a running client here. The unit test models the
  flag and the raw pass-through; the client proves the opacity.
- **StatusBar secret acceptance in practice.** `AllowedWhenTainted` + `BarValue` is
  documented (and Blizzard's mana bar relies on it), but the tainted-addon case was not
  observed in-client.
- **`Interface\\Buttons\\WHITE8X8` on the Forever/Camelot client.** It is
  LibSharedMedia's "Solid" statusbar texture (used by addons across all client families)
  and is vendored in this repo's `Libs/`, but it does not appear literally in the
  wow-ui-source tree, so asset presence on Forever is UNVERIFIED. If the fill ever
  renders untinted/blank, swap `pb.STATUS_BAR_TEXTURE` to
  `Interface\\TargetingFrame\\UI-StatusBar` (the texture Blizzard's XMLs use on Forever).
- **FontString-over-track layering.** Parented to the StatusBar for correct draw order;
  standard WoW layering, not observed in-client.
- **Perceived appearance during restricted combat.** The bar should be visible with the
  correct colour and a `?` label; the operator's eye is the acceptance test.
- **Expected in-client observation:** enter combat on Forever with a class whose primary
  power is restricted (e.g. mana class in a restricted context) → the power bar stays
  visible under the melee row and the label shows `?`; `/st diag` (verbose) then shows
  `power ... value=restricted fraction=? why=-`. If the bar is still missing, the diag
  `why=` token now names the remaining gate (`no-anchor`, `no-api`, `no-type`, ...).

**Do not read this report as in-client proof.** Everything above is offline evidence,
documented API contracts, and mutation-verified unit behaviour.
