# Secret HUD fix — restricted trinket cooldown reads keep the slot (2026-11-06)

- **Desk:** `secret-hud-fix` (writer). Files: `hud.lua`, `tests/hud_state.lua`, this
  report, `desks/secret-hud-fix/**`. **No git, no version fields, no TOCs/docs/run.sh,
  no other desk's file.** LF preserved.
- **Fix:** audit **SEC-10** (`bench/secret_consumers_audit_2026-11-06.md`): on WoW Forever
  a restricted item-cooldown read degrades to `0,0,0`; the HUD read `use_enable == 1` →
  false, so an equipped **on-use trinket's HUD slot silently disappeared**. The HUD now
  consumes the new additive fourth `restricted` return of `api.GetInventoryItemCooldown`
  (`bench/secret_guide_fix_2026-11-06.md` §2, `compat.lua:1556`) and keeps the slot
  visible in the existing restricted face: greyed, **no swipe, no fabricated countdown**.
  A readable passive stat stick still hides; a readable on-use trinket still shows exactly
  as before.
- **Priors read:** consumers audit (executive table, SEC-10, L5, §3 "the Forever HUD is
  restricted-aware"), secret-guide-fix §2 (fourth-return contract; §5 note "SEC-10 is the
  secret-hud-fix lane's"), secret-api-matrix §6 (sink matrix: `CooldownFrame:SetCooldown`
  is `AllowedWhenUntainted` — the swipe cannot be driven from a restricted read, so the
  unknown face is the correct answer; `FontString:SetText` is string-only), the current
  `hud.lua` trinket path + `HUD.paint` restricted face.

## Root cause (verified in code)

`hud.lua` before this pass:

- `trinket_has_on_use(inv_slot)` (`hud.lua:337-343` old) read **three** returns:
  `local _, _, use_enable = api.GetInventoryItemCooldown(inv_slot)` and returned
  `use_enable == 1 or use_enable == true`. compat's restricted path returns
  `0, 0, 0, true` — so the degraded idle zero read as **passive**.
- `HUD.trinket_usable` returned that `false`; `HUD.icon_should_show`
  (`hud.lua:801-812` old) returned it directly, and `HUD.trinket_state`
  (`hud.lua:394-409` old) did `if not HUD.trinket_usable(...) then s.hidden = true`.
  Result: **slot hidden** — a feature silently disappears (FD), exactly SEC-10.

The restricted *paint* face already existed and was correct (`HUD.paint`,
`hud.lua:1247-1252` / `:1294-1306` / `:1332`): `s.restricted == true` skips the
`SetCooldown` swipe and the countdown text and forces desaturation. The defect was purely
that the trinket state machine never set the flag and never read the fourth return.

## Fix (`hud.lua`)

1. **`trinket_has_on_use` is tri-state** (`hud.lua:335-353`): reads the fourth return;
   `restricted == true` → **nil** (unknown), `use_enable == 1/true` → true, else false. A
   client with no cooldown reader at all keeps the historical `false` (inert, not unknown).
2. **`HUD.trinket_usable(t, inv_slot, use_enable, use_restricted)` is tri-state**
   (`hud.lua:355-375`): empty/no-item → false; a known `TRINKET_DATA` buff or a live
   proc/ICD stamp → true (readable evidence beats an unknown cooldown); `use_restricted`
   → nil; otherwise the readable enable flag. The optional cached pair keeps the tick at
   one live read; `icon_should_show` still probes on its own (layout path only).
3. **`HUD.trinket_state`** (`hud.lua:403-448`) resets `s.restricted = nil` every tick (the
   state table is reused, so the flag cannot leak/latch), reads the four-value result,
   and:
   - `usable == false` → `s.hidden = true` (readable passive/absent — unchanged);
   - `usable == nil` → `s.restricted = true` and the **once-per-session chat notice**;
   - the on-use swipe branch is gated on `not s.restricted`, so an unknown read can never
     arm a swipe even if the degraded zeros were nonzero.
4. **`HUD.icon_should_show`** (`hud.lua:829-845`): `HUD.trinket_usable(...) ~= false` —
   only a **confirmed** "not usable" hides; unknown keeps the slot visible.
5. The notice (optional per dispatch, cheap): flag `HUD.trinket_restricted_notified`, one
   `st.utils.print_msg` per session through `pcall` (same style as the CLEU-register
   notice) — *"trinket HUD slot N is shown grey: this client hides item cooldown timing (a
   restricted read), so no timer is painted. This notice appears once per session."*

`HUD.paint` was **not** changed: the existing restricted face already does what the fix
needs. compat's wrapper was **not** changed (read-only for this lane) — the HUD consumes
its documented fourth return.

## Tests (`tests/hud_state.lua`)

The fixture now models real secrets instead of mocking the wrapper: `env.issecretvalue`
(a value-keyed `SECRETS` sentinel table, paladin_state's pattern, reset per build) and the
raw `GetInventoryItemCooldown` fixture returns `secret(900301..900303)` when
`item_cooldowns[slot] = { restricted = true }`. The **real shipped compat wrapper** then
performs its degrade and emits `0,0,0,true`, so the §20b pins exercise the production
contract end to end.

New **§20b** (`tests/hud_state.lua:2858`, 36 checks):

- (a) restricted `(0,0,0,true)` on an equipped on-use trinket: wrapper returns the idle
  zeros + `restricted == true`; `trinket_usable` → **nil**; `icon_should_show` → **true**;
  `trinket_state` has `hidden == nil`, `restricted == true`, no `remaining`/`duration`/
  `text_remaining`; the driver tick (`refresh_layout_cache` + `update_display`) shows the
  icon, paints no swipe and no text, and desaturates it.
- (a2) paint defence-in-depth: a state that carries timing **and** `restricted` clears any
  previous swipe (never replaces it), hides the cooldown frame and the text, stays grey; a
  fresh icon gets **no `SetCooldown` call at all**.
- (b) readable passive (`0,0,0`, no fourth) still `trinket_usable == false`, still hides,
  and is not marked restricted.
- (c) readable on-use (`enable == 1`) still shows normally; the restricted flag does not
  latch on the next readable read.
- Notice: exactly one chat line on the first restricted paint, never per tick (3 ticks
  → still 1).
- Control: a known proc buff stays usable even when the cooldown read is restricted
  (readable evidence wins).

## Red-first → green evidence

- **Before the hud.lua fix** (same suite): **10 of 895 checks failed**, exactly the
  intended pins — restricted probe `(got false, want nil)`, slot visible `(got false,
  want true)`, state not hidden `(got true, want nil)`, state flag `(got nil, want
  true)`, notice count `(got 0, want 1)` ×3, driver shown/text/grey pins. No unrelated
  failure.
- **After the fix:** `tests/hud_state.lua` → **PASS, 895 checks** (baseline 859, +36).
- `tests/forever_hud_gate_state.lua` → **174 checks, 0 failed** (its trinket gate cases
  B/C/D read three values; the tri-state path is unchanged for them).
- `tests/secret_guard_state.lua` → **PASS, 524 checks**.
- `bash tests/run.sh` → **57 steps, 0 failed** (this tree, after the fix; run twice,
  same result).
- `luacheck hud.lua tests/hud_state.lua` → **0 warnings / 0 errors**; whole-tree floor
  unchanged at **2 warnings / 0 errors in 100 files**; `luac5.1 -p` clean; LF preserved
  (0 CR lines both files); no lint-config change, no `_` silencing.

## Mutation proofs (isolated `/tmp` source copies; one deliberate break each)

| # | Mutation | Result |
|---|---|---|
| M1 | restricted on-use treated as readable passive (`return false` instead of nil) — i.e. the old hide-on-unknown behaviour | **KILLED**, 5 fails: tri-state probe, slot visible, driver shown, driver text, driver grey |
| M2 | `HUD.paint` restricted flag no longer suppresses the swipe/text (`not restricted` removed from both gates) — "paint a swipe/text on restricted" | **KILLED**, 5 fails: swipe cleared (got 6), cooldown frame hidden, no countdown text, fresh-icon no-`SetCooldown`, fresh-icon frame |
| M3 | HUD ignores the fourth return (3-value reads in both helpers) — "ignore the fourth return" | **KILLED**, 10 fails: the whole tri-state/notice/driver set |

Each mutation run kept the rest of the 895 checks green; only the SEC-10 pins failed.

## Files changed

| File | Change |
|---|---|
| `hud.lua` | tri-state `trinket_has_on_use` / `HUD.trinket_usable`, restricted state + reset in `HUD.trinket_state`, `icon_should_show ~= false`, once-per-session notice |
| `tests/hud_state.lua` | secret-value fixture (`issecretvalue`/`SECRETS`, restricted raw cooldown returns), new §20b (36 checks) |
| `bench/secret_hud_fix_2026-11-06.md` | this report (new) |
| `desks/secret-hud-fix/**` | desk journal + done signal |

## UNVERIFIED (in-client only — nothing below is claimed)

1. **No in-client proof.** Everything above is offline evidence on the real modules +
   the shipped compat contract. The operator's Forever client was not observed.
2. Whether the operator's equipped trinkets actually hit the restricted regime (the
   wrapper's trigger) — the audits' trigger-confidence is MED; `/st diag` prints the
   secret switches (`diag.lua`), but the trinket read has no diag receipt yet (L4
   follow-up).
3. The rendered restricted face (grey, no timer) and the notice wording — behaviour is
   pinned through `HUD.paint`'s state → calls mapping, not through a client screenshot.
   (No `?` marker was added; that remains L5's display-only operator decision.)
4. The fourth return's shape on a live 1.60.1 `GetInventoryItemCooldown` (secret fields,
   SpellCooldownInfo table) is compat's contract, pinned in `tests/paladin_state.lua` §21
   and `tests/forever_secret_compat_state.lua`; this lane consumes it, it does not
   re-prove the client.
5. Retail 12.x (same Mainline secret regime, audit M5): the trinket path is
   family-agnostic and now handles a restricted fourth return if the client+compat
   produce it; whether Retail's item cooldown actually restricts is UNVERIFIED.

## Follow-ups NOT done (deliberately)

- **L5 `?` marker on the restricted HUD face**: the audit's minimal fix draws a constant
  `?` in the icon text (power_bar precedent). The dispatch scoped this lane to SEC-10 and
  made the notice optional; the `?` is a display-only operator decision, left for the
  display/UX lane or the operator's ruling. The notice now explains the grey state in the
  meantime.
- **L4 `/st diag` restricted-cooldown receipt**: `diag.lua` is another desk's file; a
  `cd_restricted` counter would make the next in-client pass close the trigger question.
- **`tests/forever_hud_gate_state.lua` restricted trinket case**: that suite's trinket
  gate blocks stub three-value reads; a restricted leg there would duplicate §20b and the
  file is outside this lane's write scope (filed, not edited).
