# buildout_paladin — P1/P2/P3/P6/P7 + CD icon group (build-out round 1)

Date: 2026-10-17. Desk: paladin (finisher; the previous attempt died mid-flight on a rate limit). Brief: `bench/briefs/brief_paladin_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").

## 1. Changes

Writable scope held: `classes/paladin.lua`, `nextaction.lua` (previous-attempt work kept, no finisher edits), `nextaction_ui.lua` (unchanged), `tests/nextaction_state.lua` (extended), `tests/twist_state.lua` (untouched — pins intact), NEW `tests/paladin_state.lua`. No other file touched; no git ops. `tests/run.sh` registration is owned by the enemy-swing lane (its brief) and has already landed (`run "lua5.1 tests/paladin_state.lua"`, step 65).

State found at handoff: all six features were already present in the dead attempt's files (P1 counters/badge, P2 JotC bar + melee refresh, P3 lust scan + `apply_lust_window`, P6 pulse start/stop, P7 texture latch, CD row). The finisher inspected and kept that work, then cleared the brief's failures:

1. **P6 dead hook (the brief's hard failure).** `ST.PALADIN.aow_exo_pulse_start(` was defined but never called. Now called at the false→true overlap transition inside `process_aow` (classes/paladin.lua:473), the twist-success-glow shape: start at the transition, the per-frame stop block owns expiry/option-off teardown. The start also carries the Retail gate the sibling paladin visuals share (`and not st.is_retail`): Retail has neither the proc nor the per-frame stop path, so an un-gated start could never be stopped there.
2. **P3 gate consumes the landed C2 contract.** Replaced the previous `not is_era_family` with `st.lust_supported ~= false` (classes/paladin.lua:1007) — compat.lua's own consumer rule ("consumers gate on st.lust_supported"); Era and the UNKNOWN fallback are closed, nil (pre-C2 compat) degrades to the scan-only behaviour. The ids stay the frozen 2825/32182 pair in the scan predicate.
3. **Combat-exit pulse teardown made conditional** (classes/paladin.lua:1429): only a live pulse (`aow_exo_pulse_until > 0`) is stopped. The previous unconditional stop emitted a stray `LCG.PixelGlow_Stop` on every combat exit and broke the existing `bars_state` pin "glow: combat exit stops the glow"; with the conditional that pin passes unchanged (verified).

### Feature summary (as shipped)
- **P1 live twist hit-rate badge** — `twist_score_attempts/successes` count at the top of `on_twist_attempt`/`on_successful_twist`, ahead of every feedback gate (truth independent of visuals). Session-scoped by default; `twist_score_persist == true` restores from / mirrors into the class profile. The badge is a 12 pt fontstring below the bar, one quantised `"N% (S/A)"` string per state change, shown only in combat with the option on.
- **P2 JotC uptime mini-bar (21183, 20 s max rank)** — 0.5 s-throttled HARMFUL target scan; max-rank melee refresh via `note_swing_landed` (called from the CLEU SWING_DAMAGE/SWING_MISSED branch after the extra-attack discipline); lower ranks fixed at 10 s, never refreshed; seal-icon idiom (icon + inverse swipe + timer text), all draws latched. Combat exit clears the tracker.
- **P3 lust override** — 0.5 s-throttled `st.api.scan_player_aura` over ids 2825/32182; the window scales through the pure `st.nextaction.apply_lust_window(window, lust ~= nil)` (scale 0.6, floored at 0, nil-safe passthrough). Era/UNKNOWN never arm; a running practice session owns its own window.
- **P6 AoW+Exo overlap pulse** — one gold Pixel pulse (key `AowExoOverlap`, 0.4 s, 8 lines / 0.25 / thickness 2) per false→true transition of "AoW up AND Exorcism castable" (the `require_exo_ready` gate applied); transition latch updates with the option off, so a later enable never fires on a stale overlap; stop on expiry, option-off, combat exit.
- **P7 seal-icon texture churn** — per-slot lazy texture cache; `GetSpellInfo` runs only until the first non-nil answer (a cold miss is never cached), `SetTexture` only on show/identity change. No per-frame resolution or SetTexture in steady state.
- **CD icon group** — adaptive inverse-swipe row left of the JotC mini-bar (re-anchors when that hides/shows), gold glow through the final 4 s, 0.5 s-throttled absolute-expiry reads, GCD echo (duration ≤ 1.51 s) never counts, racial slot resolved from the spell book and hidden until resolved. Ids in §3.

## 2. Option defaults (standing-rule record for the options pass)

All six keys are **nil = OFF today** and absent from `config_presets.lua` / the option tables — adding widgets + defaults is the options pass's job. Reads are nil-safe (`== true` for enable, `== true` for persist).

| Key | Shipped default | Read as | Behavior when on |
|---|---|---|---|
| `twist_score_enabled` | nil (off) | `== true` | Shows the hit-rate badge in combat |
| `twist_score_persist` | nil (off) | `== true` | Restores + mirrors session counts in the class profile |
| `jotc_bar_enabled` | nil (off) | `== true` | Shows the JotC uptime mini-bar |
| `twist_lust_override_enabled` | nil (off) | `== true` | Narrows the twist window while Bloodlust/Heroism is up |
| `aow_exo_pulse_enabled` | nil (off) | `== true` | Pulses on each AoW+Exo readiness transition |
| `cd_icons_enabled` | nil (off) | `== true` | Shows the CD icon row |

No default-visible change on any client.

## 3. CD icon group — id table

Row order (left to right; the container hugs the bar / JotC bar and shows only active cooldowns):

| Slot | Id | Status / notes |
|---|---|---|
| Avenging Wrath | 31884 | CONFIRMED (archive HUD id) |
| Divine Shield | 642 | rank-1 id, resolves every family |
| Hammer of Justice | 853 | rank-1 id, resolves every family |
| Hand of Protection (BoP) | 1026 | rank-1 id, resolves every family |
| Holy Wrath | resolver: 48817, 48816, 27139, 10318, 2812 | first known rank wins; rank-1 2812 carries the fallback texture. Ranks UNCONFIRMED as a set — confirm in-client |
| Lay on Hands | 633 | rank-1 id, resolves every family |
| Racial | 20594, 20572, 26297, 20549, 28730, 20600, 28880, 7744 | UNCONFIRMED candidate list (bench/discover_features.md row 5 "ids need verification"); resolved only via `IsSpellKnown` over the book, slot stays hidden until one resolves |

Glow constants: `CD_GLOW_LEAD` 4 s, key `CdReadySoon`, colour {255, 215, 0, 0.9}, Pixel 8 lines / 0.25 freq / thickness 2.

## 4. Tests + evidence

### tests/paladin_state.lua (NEW — 165 checks)
Real-module sandbox (compat + utils + twist + nextaction + classes/paladin.lua over frame/API stubs, the hud_state.lua pattern; controllable clock). Sections: surface + `post_init` construction (incl. CD slot order and the TBC seal-slot ids); P1 counters + persist + badge show/hide/no-churn; P2 `note_swing_landed` semantics (max rank extends to now+20; lower rank / expired / untracked / empty state untouched) and the real CLEU chain (plain swing refreshes, extra-attack swing does not); P2 mini-bar scan/swipe/timer latches, throttle, rank switch, option-off, no-target; P6 transition guard, real cast path + C_Timer completion, stale-enable protection, per-frame stop, combat-exit conditional teardown, Retail never arms; P7 cold retry / cache / no per-frame work / show transition / Era Righteousness slot (21084); P3 TBC narrow + throttle, Era and UNKNOWN never arm, practice passthrough; CD row behavior, glow latch, GCD echo, option-off, JotC re-anchor, Retail inert; static wiring pins (pulse start call, Retail gate, C2 gate, JotC CLEU call).

### tests/nextaction_state.lua (extended, +11 checks)
`LUST_TWIST_WINDOW_SCALE == 0.6`; `apply_lust_window` scale cases (0.4→0.24, 0.54→0.324, 0.8→0.48), inactive/nil passthrough, zero/negative/nil/non-number edges. Existing 415 checks unchanged.

### tests/twist_state.lua
Untouched; all 39 pins green (`PASS twist_state.lua (39 checks)`).

### Harness
`bash tests/run.sh` — my lane's suites all green at final check: `paladin_state.lua` PASS 165, `nextaction_state.lua` PASS 426, `twist_state.lua` PASS 39, `wiring_check.lua` PASS (383 checks, 0 failures; the pulse start now reports `classes/paladin.lua:396 … has a call site (classes/paladin.lua:473, qualified dispatch)` and `classes/paladin.lua:473 self.PALADIN.aow_exo_pulse_start( resolves to classes/paladin.lua:396`). The run.sh total is a moving target while other lanes land; at the final capture it was 35 steps with failures in other desks' in-flight files only (druid smoke error, shaman weave/counts, druid guide, warrior/hunter/druid bars_state counts, hud druid/warrior) plus the paladin bars_state count reconciliation this brief defers (§5).

### luacheck
Scope files: **0 errors**; `classes/paladin.lua` 2 warnings — both pre-existing trailing whitespace in untouched comment lines (485, 494); `nextaction.lua`, `nextaction_ui.lua`, `tests/paladin_state.lua`, `tests/nextaction_state.lua`, `tests/twist_state.lua`: 0 warnings.

### Mutation proofs (final state, `/tmp/opencode/mut_paladin/`)
1. **P2 refresh-on-melee** — replaced `self.jotc_expires = now + (self.jotc_full or JOTC_DEFAULT_FULL)` with a no-op assignment: `paladin_state.lua` → **3 FAIL** (direct extension, CLEU chain, bar-update path), exit 1. Restored → PASS 165, exit 0.
2. **P6 wiring** — removed the `self.PALADIN.aow_exo_pulse_start(self)` call: `wiring_check.lua` → `FAIL classes/paladin.lua:396 ST.PALADIN.aow_exo_pulse_start( is defined but NEVER called from any module - dead hook`, exit 1. Restored → 383 checks, 0 failures.

### Frame/texture/fontstring counts (for the bars_state reconciliation wave)
New paladin widgets this round, **+18 frames, +8 textures, +2 fontstrings, +0 lines**:
- JotC mini-bar: +3 frames (container, cooldown, timer frame), +1 texture (icon), +1 fontstring (timer).
- CD icon group: +15 frames (container, 7 slot frames, 7 cooldowns), +7 textures (icons), +0 fontstrings.
- Twist hit-rate badge: +1 fontstring.
Expected `bars_state` deltas: PALADIN frames 11→29 (pre-init 10→28), textures 6→14, fontstrings 6→8, lines 2 (unchanged). The "glow: combat exit stops the glow" count pin now passes unchanged (see §1.3).

## 5. Deferred / out-of-scope observations (not fixed here)
- `bars_state.lua` paladin count checks (frames/textures/fontstrings + pre-init) — reconciled in the later wave per the brief; deltas above.
- Other lanes' in-flight failures observed at final capture (not paladin): `tests/smoke.lua` (classes/druid.lua:116 `get_class_table` nil), `tests/weave_state.lua` / `tests/shaman_state.lua` / `tests/druid_guide_state.lua` (shaman/druid landings), `tests/bars_state.lua` warrior/hunter/druid counts, `tests/hud_state.lua` druid/warrior. Reported, not touched.

## 6. UNCONFIRMED / in-client check list
- Racial candidate ids (§3) — the list is a probe order, not a confirmed set; the slot stays hidden until the book answers. Verify each racial on a real client.
- Holy Wrath resolver ranks (48817/48816/27139/10318/2812) — confirm which rank the client reports.
- JotC melee refresh: relies on SWING_DAMAGE/SWING_MISSED landing for the player on the classic-line CLEU; confirm the refresh cadence and the 20 s max-rank behaviour in-client (lower-rank 10 s per the verify_bank notes).
- P3 consumer path: ids 2825/32182 are CONFIRMED (verify_bank §2); the scan + 0.6 scale are the un-eyeballed part — confirm the window visually under a real Bloodlust.
- P6 pulse constants (0.4 s / colour / thickness) and P1 badge copy are cosmetic; confirm in-client.
- Forever family: the P2/P6/P7/CD gates use `st.is_retail` (not `st.is_mainline`), so the Forever client runs them like the classic line; only in-client swing activity can confirm the visuals there.
