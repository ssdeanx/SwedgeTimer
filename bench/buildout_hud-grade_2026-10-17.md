# buildout hud-grade — HUD enterprise review (2026-10-17)

Date: 2026-10-17. Desk: hud. Brief: `bench/briefs/brief_hud-grade_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").
Scope held: `hud.lua` only (one fix). `rotationtext.lua` audited, no change needed. `tests/rotationtext_state.lua` untouched (nothing to pin). `tests/hud_state.lua` NOT touched (forbidden — deltas reported in §6). No git. No lint-config. Endings preserved (CRLF on hud.lua, verified with `file` + `\r` count 1043/1043 lines).

## 1. The fix — provider-hidden slots stayed drawn (hud.lua, update_display)

**Bug (half-wiring, found by this review):** `HUD.update_display` skipped `paint` for `s.hidden` states but left the icon **shown** with its last paint. Every class provider returns `hidden=true` for a dead slot (druid Mangle on runeless Era, TF/Berserk where the client's spell data carries no such spell), so those slots drew a live-looking icon for a spell the client does not have — shows when it should hide — and kept a stale proc glow.

**Fix (hud.lua, in `update_display`, no other file):**
- `s.hidden` → `icon:Hide()` + `PixelGlow_Stop` + glow-flag clear (mirrors the toggle-off path in `apply_settings`).
- not-hidden → `icon:Show()` if hidden (a slot revived by a later liveness retry rejoins the row without waiting for a settings change).
- `s == nil` → untouched (previous behavior; no provider returns nil on a live path).
- `paint`'s hidden early-return stays as defense.

Show/Hide on these non-secure row frames is combat-safe (only creation is lockdown-gated, unchanged). Nil-safe (all reads guarded by existing `s and` checks). No default-visible change (toggle-off and empty-trinket paths untouched).

## 2. Slot-by-slot verification table (code audit + suite pins)

Legend: S = shows when it should, H = hides when it shouldn't be drawn, U = updates from live state each tick. Evidence codes: HSxx = tests/hud_state.lua section, suite name + checks = read-only run this review.

### PALADIN — cs, judgement, consecration, exorcism, trinket1, trinket2, wings (HS §§4-8; paladin_state 165 PASS)

| Slot | S | H | U | Notes |
|---|---|---|---|---|
| cs | toggle on (default true) | toggle off | 6 s client CD swipe + desat + text; GCD swipe when ready | practice-aware (sim fields) |
| judgement | toggle on | toggle off | 8 s CD; NO GCD borrow (archive rule); greys without an active seal | seal-less grey pinned |
| consecration | toggle on | toggle off | 8 s CD + GCD; blue mana tint via hud_mana_tint | — |
| exorcism | toggle on | toggle off | 15 s CD + GCD; greys unless Undead/Demon; **glows when castable in combat** (prior-pass behavior live) | rank-1 id 879, name-based reads |
| wings | toggle on | toggle off | 180 s real CD; NO GCD borrow; **glows ready in combat** | archive parity |
| trinket1/2 | toggle on + item equipped | toggle off; empty slot (outside design mode) | on-use CD > proc buff > reversed ICD swipe; CLEU optional/best-effort | HS §6 machine pinned |

Prior-pass **HoW**: lives in the **guide** (`how` slot, HOW_RESOLVE_RETRY_S cadence) + the bars CD icon group — deliberately no HUD slot (HUD mirrors the archive's 7-slot row). paladin_state §§ cover HoW resolve/fallback; no HUD gap.

### HUNTER — steady, raptor, kill_command, multi, bestial_wrath, rapid_fire, aimed, t1, t2 (HS §13; hunter_state 448 PASS)

| Slot | S | H | U | Notes |
|---|---|---|---|---|
| steady / raptor | toggle on | toggle off | running GCD swipe + mana/range tints (no native CD) | — |
| kill_command | toggle on | toggle off | 60 s CD; **glows ready in combat** | GCD-echo filtered |
| multi | toggle on | toggle off | 10 s CD | — |
| bestial_wrath / rapid_fire | toggle on | toggle off | 120 s / 300 s CDs; never borrow GCD | — |
| aimed (prior-pass) | toggle on (`hud_show_aimed` pinned) | toggle off | rank-1 id ships (19434), **re-pointed at post_init to the client's rank** (HS pins 20904); Era 6 s CD by localized name; off-Era falls through to GCD swipe | re-point runs before hud.init — no stale icon |
| trinkets | as paladin | as paladin | as paladin | — |

### WARRIOR — TBC: op, execute, slam, hs, bt, ww, t1, t2 (HS §14; warrior_state 620 PASS)

| Slot | S | H | U | Notes |
|---|---|---|---|---|
| op | toggle on | toggle off | dodge-window glow; **elapsed stamp stops the glow and skips the probe** (W7 lifecycle, HS pinned); nil-stamp probe fallback only | resolve order verified (resolve_guide_slots → hud.init) |
| execute | toggle on | toggle off | **glows ready + in combat + target in Execute range** (unreadable target never glows) | guide_execute_pct threshold |
| bt / ww | toggle on | toggle off | 6 s / 10 s real CDs | TBC values, UNCONFIRMED in-client |
| slam / hs / cleave | toggle on | toggle off | GCD swipe (no native CD) | all rotational, empty SKIP_GCD set |
| arms set (op, execute, rend, ms, bladestorm, hs) / SoD set (execute, slam, hs, bt, ww, raging_blow) | drawn | **NO TOGGLE EXISTS — see §5 finding** | generic CD + GCD path covers them (fallbacks present) | re-picked at post_init before hud.init |

Prior-pass **Rampage**: lives on the **bars badge** (W3 tier recolour, warrior_state §§ pinned), not a HUD slot — no HUD gap by design.

### DRUID — maul, mangle, rip, rake, bite, shred, tf, berserk, t1, t2 (druid_state 415 PASS; HS §15 counts deferred to §6)

| Slot | S | H | U | Notes |
|---|---|---|---|---|
| maul (prior-pass bear chain) | toggle on | toggle off | **greys while queued Maul unaffordable** (insufficient_rage); GCD swipe | Cap badge is bars-side (D6) |
| mangle | toggle on + rune-gated live | toggle off; **hidden on runeless Era** (SoD rune keeps it live) — NOW actually hides (§1 fix) | GCD swipe | engine likewise never prompts there |
| rip / rake / bite / shred | toggle on | toggle off | GCD swipe; no native CD | — |
| tf / berserk (this round) | toggle on + liveness probe live | toggle off; **hidden while the probe is negative** (5 s retry; Berserk + SoD-rune basis on ERA) — NOW actually hides | name-based real CDs (30 s / 3 min fallbacks); **glow ready in combat**; never borrow GCD | rank re-point before hud.init; druid_state §28 pins liveness + glow |
| trinkets | as paladin | as paladin | as paladin | — |

### SHAMAN — stormstrike, flameshock, weave, firenova, earthshock, twist, t1, t2 (HS §16; shaman_state 378, weave_state 417 PASS)

| Slot | S | H | U | Notes |
|---|---|---|---|---|
| stormstrike | toggle on | toggle off | 10 s CD; **glows ready in combat** | — |
| flameshock / earthshock | toggle on | toggle off | 6 s shock CD; GCD swipe when ready | rank-agnostic name reads |
| weave | toggle on | toggle off | LB icon (rank-1 403), GCD swipe, S5 mana tint wired | round-2 spell-position markers are bars-side; HUD stays LB by design (shaman-lane residual noted) |
| firenova | toggle on | toggle off | 15 s real CD by name | — |
| twist (prior-pass totem-twist) | toggle on | toggle off | Windfury Totem cooldown/GCD face | the LIVE twist (last-drop stamp → engine rule 4) drives the **guide**, not the HUD — no HUD mirror by design; S1 stays BLOCKED on WF/GoA ids |
| trinkets | as paladin | as paladin | as paladin | — |

### ROTATIONTEXT — no change (rotationtext_state 218 PASS, untouched)

Gates (disabled/provider-less/master-switched → hidden, source never called), counting-resolver pin, paladin live + practice-aware provider, all 5 class `get_rotation_key` sources, creation gates (pre-init/lockdown/provider-less inert), config/widget/TOC pins — all green. No half-wiring found: every exposed entry point is exercised, every gate has a hide path, the driver owns the in_combat transition.

## 3. Cross-cutting audit (all clear)

- **post_init order** (re-point before build): hunter `resolve_guide_icons` (L371) → `hud.init` (L380); warrior `resolve_guide_slots` (L519) → `hud.init` (L535); druid `resolve_hud_slot_icons` (L244) → `hud.init` (L253); shaman `resolve_guide_icons` (L939) → `hud.init` (L949). No stale-creation path.
- **No `st.is_mainline` gates** in scope (grep-clean); druid Era/SoD gates use `st.family` + rune probes; warrior W7 fallback is probe-only.
- **No stale values**: every provider resets the reused state table field-by-field before filling; practice/option-off paths write every field every call (shaman twist inputs cited as the pattern).
- **Design mode**: unknown-slot preview falls through to live state (informative, no frozen frames); trinket empties show fallbacks only while unlocked.

## 4. Evidence

- `lua5.1 tests/rotationtext_state.lua`: **PASS 218 checks** (untouched file, still green after the hud.lua edit).
- `lua5.1 tests/hud_state.lua` (read-only): **401 checks, 4 failed — exactly the known druid count pins** (§6), zero new failures. The §5 "provider runs exactly once" pin still holds (fix adds no provider calls).
- Class suites (read-only): warrior 620, druid 415, hunter 448, paladin 165, shaman 378, weave 417, nextaction 443, twist 39 — all PASS.
- `luacheck hud.lua rotationtext.lua tests/rotationtext_state.lua`: **0 warnings / 0 errors** (tree total 0 errors; warnings are other lanes' in-flight files).
- Full harness: **35 steps, 3 failed** = bars_state 12 + hud_state 4 (both count-reconcile pins) + **one other-lane toc_check failure** (`## Interface` missing 120100 — an in-flight toc edit, not this scope; hud.lua cannot affect Interface lines).
- **Mutation proofs on /tmp/opencode/mut_hud/** (full copy; restored byte-identical, `diff -q` clean):
  1. Fix reverted (old 3-line block): disposable `scratch_hidden.lua` (8 checks: hide on hidden / glow stop + flag clear / revive re-show) → **4 FAILs**. Restored → **8 PASS**.
  2. Copy harness after restore: same failures as repo baseline at copy time (count pins only; the toc failure and scratch-file artifacts were copy-side only and removed).

## 5. Out-of-scope findings (not fixed — wrong lane)

1. **Warrior arms/SoD HUD slots have no toggles or defaults.** Keys `hud_show_rend`, `hud_show_ms`, `hud_show_bladestorm`, `hud_show_raging_blow` exist in neither `config_presets.lua` nor `option_tables.lua` (all other 4 classes' slot keys do). `icon_should_show` reads nil → not `false` → always drawn with no user toggle. Owner: options wave (add widgets + defaults) or warrior lane (if the sets should be toggle-less by design — record the decision).
2. **Provider-hidden icons reserve row width.** Layout counts `wanted`, not liveness: a hidden-by-provider slot (runeless-Era Mangle, dead TF/Berserk) leaves a gap until a settings change reflows. Owner: reconcile wave (it owns widths/counts) — suggested shape: track last hidden state per icon and reflow on flip, deferred outside combat; weighed and deliberately NOT done here (reflow-inside-update_display breaks the "at most once per tick per slot" provider contract and the HS §5 exactly-once pin).

## 6. Count deltas for the reconcile wave (report-only; tests/hud_state.lua + tests/bars_state.lua untouched)

- `tests/hud_state.lua` §15 druid (current code): `#slots == 10` (got, was 8); order `maul, mangle, rip, rake, bite, shred, tf, berserk, trinket1, trinket2`; `#DHUD.icons == 10` (was 8); row width `8 * 36 + 7 * 2 == 302` (was 226). 4 failing checks, all §15, all count/order — no behavioral failure.
- `tests/bars_state.lua` (current tree, other lanes' additions included): PALADIN frames 29/textures 14/fontstrings 8 (want 11/6/6); WARRIOR textures 34/fontstrings 19 (want 33/17); HUNTER frames 20/textures 23/fontstrings 13 (want 18/17/11); DRUID frames 7/textures 21/fontstrings 9 (want 6/14/7); pre-init 28 (want 10). 12 failing checks, all count rows.
- This lane's fix changes **no counts** (no frames/textures/fontstrings added or removed; hide/show only).

## 7. UNCONFIRMED / in-client checks (offline cannot load the addon)

All visuals below are verified-offline only: icon hide/show transitions, glow stop timing, row reflow behavior with dead slots, TF/Berserk liveness on real clients (Era runeless hides Mangle/Berserk; Forever's absent TF hides the slot), Aimed re-point art on rank-up, trinket ICD reversed swipe under a live CLEU, rotation-label agreement with each class guide in-game. In-client session owns these.

Bench rule honoured: nothing overwritten; this is the hud lane's single report file. Cross-references: `desks/hud/journal.md`, `desks/hud/.signals/20261017T145851Z.json`, `bench/briefs/brief_hud-grade_2026-10-17.md`, the five class buildout reports, `bench/lessons.md`.
