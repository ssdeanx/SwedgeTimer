# buildout_shaman — build-out round 1 (S2 / S3 / S4 / S5 + Rockbiter + shield charges)

Date: 2026-10-17. Desk: shaman. Brief: `bench/briefs/brief_shaman_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").
S1 totem twist: untouched — BLOCKED (WF/GoA ids UNCONFIRMED, brief §Task).

## 1. Changes

Writable scope held exactly: `classes/shaman.lua`, `weave.lua`, `tests/weave_state.lua`, `tests/shaman_state.lua`. No other file touched; no git ops.

### S2 — Stormstrike nature-vuln target bar (STANDARD)
- `weave.lua`: `STORMSTRIKE_FALLBACK_DURATION = 12`, `STORMSTRIKE_GLOW_SECONDS = 4`, pure `get_stormstrike_remaining(duration, expiration, now)` + `should_stormstrike_glow(remaining)` (Flame Shock pair shape; lines 365-390).
- `classes/shaman.lua`: id table `{ [17364], [32175] }` + name fallback ("Stormstrike"), FS-bar-clone styling constants (nature-teal), `scan_target_debuffs(want_stormstrike)` (one walk; FS leg keeps the old early exit, SS leg only runs when the bar is on), `refresh_target_debuffs(self, db, now)` (shared 0.05 s throttle with the guide's FS input), `update_stormstrike_bar(...)` stacked above the FS bar (fill + seconds label + final-4 s glow). Widgets are **created lazily** on the first tick with the option ON.
- Reads stay guarded: nil-safe id lookups + name compares, caster must be the player (nil source allowed, the port's FS convention), non-number payloads fall back per the pure helper.

### S3 — WF-fishing HOLD tint (STANDARD; bank S3 = "amber wash on the bar's final fraction")
- `weave.lua`: `should_hold_stormstrike(windfury_icd_remaining, swing_remaining)` (mirrors the frozen engine's private `should_delay_stormstrike`, rule 7; lines 305-321) and `get_wf_hold_wash_fraction(swing_elapsed, swing_duration, icd_remaining)` (start fraction of the final-fraction wash; lines 323-333).
- `classes/shaman.lua`: SS badge flips to an amber **"SS HOLD"** while holding (mode-switch forces a text refresh so a stale "SS HOLD" can never survive into the cooldown text), and `update_wf_hold_wash(...)` draws a translucent amber overlay over the swing's final fraction — from the WF-ICD clear point to the swing end (lazy texture, OVERLAY -4). Both are gated by the new nil-off `show_shaman_wf_hold_tint`; the wash additionally requires Stormstrike ready (the engine's rule-7 order). Gate is swing activity only — **no `st.is_mainline` gate anywhere** (Forever keeps weaving).

### S4 — MW5 spender choice (correction §4.3 — BINDING)
- `weave.lua`: `get_mw5_spender(lava_burst_known)` → `"lavaburst"` ONLY on strict boolean-true (the SoD rune/talent gate; every other reading → `"lightning"`), `MW5_FS_GUARD_SECONDS = 2`, `should_hold_mw5(flameshock_remaining, shock_ready)` → hold the five-stack weave while FS < 2 s AND the shock cooldown is strictly ready (bank S4: "hold weave if FS < 2s and shock ready"). `LAVA_BURST_COLOR` for the marker tint.
- `classes/shaman.lua`: `resolve_lava_burst(self)` (ERA-only name-probe → id → icon/cast, cached + throttled; cleared by `on_talents_changed`), the MW5 branch of `get_weave_visual_spell` (Lava Burst entry + `"LvB"` family token only when `api.is_spell_known(lava_id)` is true and the guard does not hold), `is_shock_ready()` (rank-agnostic localized-name Flame Shock cooldown read, same GCD-echo filter as the guide), and the gather guard: while MW is active and `should_hold_mw5` holds, the gather feeds `mw_available = false` — the frozen engine then falls through to its Flame Shock refresh (rule 5). Stack counts stay truthful; every frozen field is still written every call.
- **Interpretation note (recorded, not source-verified):** the bank text is "5-stack choice rule (LB vs LvB by family/rune) + FS-collision guard (hold weave if FS < 2s and shock ready)" (bench/brainstorm bank S4). Implemented literally: the choice is the assist's MW5 marker icon; the guard suppresses the weave via the only in-scope lever (the gather). Boundary: exactly 2.0 s does NOT hold (strict <); nil/NaN FS and unknown/non-true shock never hold (no hold on a guess).
- **Scope split (must be stated):** the guide slot's post_init LvB re-point (`resolve_guide_icons`, ERA-only) keeps its **client-data** gate (name resolves) because its sibling suite `tests/shaman_guide_state.lua` is out of this brief's writable scope and pins that shape ("re-points when the rune is known" = spell data present). The **player-level rune/talent gate** therefore lands on the assist's MW5 marker, which is covered by this lane's suites. On an Era-base character whose client data has LvB but no rune: the assist shows Lightning Bolt (gated); the guide slot (default OFF) would still show the LvB icon — reconcile item for the options/wave that can touch both.

### Rockbiter Weapon badge (discover #6)
- `WEAVE_ROCKBITER_IDS = { [8017] }` (rank-1 id sourced from the read-only reference `SuperSwingTimer_ClassMods.lua:4217`; ranks above 1 match by the English name only — their ids stay UNCONFIRMED and are never guessed), name fallback + expiry read in the merged aura walk, `update_rockbiter_badge(...)` ("RB 287s" while up, bare "RB" when the expiry is unreadable, hidden otherwise; lazy fontstring). New nil-off `show_shaman_rockbiter_badge`.

### Shield charge tracker (discover #7) — pre-check + extension
- **Pre-check result (verified against current code first):** coverage EXISTS. `scan_weave_auras` already reads the active shield's type + charge count, `st.weave.get_shield_tracker_state` clamps it, `update_shield_charges` renders one rect per slot (filled / dimmed). Nothing was missing from the "remaining-charge state" itself.
- **Extension made:** the unreadable-count fallback was the optimistic full row; the reference falls back to the **3-charge standard** (`SuperSwingTimer_ClassMods.lua:4141-4144`: `if not chargeCount then chargeCount = 3`, 3-rect row at :3514). `get_shield_tracker_state` now fills `SHIELD_FALLBACK_CHARGES = 3` (clamped to slots) for nil / non-number / < 1 counts — Lightning with an unreadable count shows 3 filled + 1 dimmed, Water stays 3/3. This port keeps the extra 4th Lightning slot (era/talent variants; `tests/bars_state.lua` pins the 4-rect row and was not touched).

### S5 — mana tint verify/wire
- **Verified wired, no gap found:** `ST.SHAMAN.get_hud_state` reads the shared `hud_mana_tint` key and marks `s.usable = false` on an insufficient-power reading (`classes/shaman.lua:2246-2248`); the shared default ships true (`config_presets.lua:59`); `hud.lua:887` applies the blue tint on `s.usable == false`. All shaman HUD slots (incl. the shock slots) ride the same path. Pinned by new test section 26.
- **Residual (one line, not fixed):** the HUD weave slot probes "Lightning Bolt" (403) even where the guide slot re-points at Lava Burst on SoD — a cosmetic HUD-lane item, deferred.

### Widget inventory (for the later bars_state reconcile wave)
Construction-time counts unchanged (all new widgets are lazy): SHAMAN mainhand still creates 13 textures + 3 fontstrings, offhand +1 texture → **bars_state's SHAMAN counts still pass**. With the new options ON and a mainhand tick: S2 bar = +3 textures +1 fontstring; WF wash = +1 texture; RB badge = +1 fontstring → SHAMAN totals become 18 textures / 5 fontstrings when all three toggles are enabled.

## 2. Option defaults (standing-rule record for the options pass)

| Key | Shipped this round | Intended default (options pass) |
|---|---|---|
| `show_shaman_stormstrike_bar` | absent; read `== true` → **nil = off** | true (S2 standard tracker) |
| `show_shaman_wf_hold_tint` | absent; read `== true` → **nil = off** | true (S3 standard cue) |
| `show_shaman_rockbiter_badge` | absent; read `== true` → **nil = off** | true (discover #6) |

No default-visible change in any client this round; widgets exist only after a toggle is turned on. S4 adds no new key (rides the existing `weave_mw_enabled` kill-switch and the existing marker visibility). The shield-fallback correction is behavior under the existing `show_shaman_shield_charges` (only the unreadable-count shape changed — reference-cited above).

## 3. Evidence

- `bash tests/run.sh` (in-repo, final state): **35 steps, 2 failed** — both failures are other lanes' frame-count reconciliation items, with ZERO shaman failures: `bars_state.lua` (PALADIN/WARRIOR/HUNTER/DRUID created-count expectations; SHAMAN checks all pass) and `hud_state.lua` (druid slot counts). Baseline before this lane's edits was the same 2 failing steps (captured `/tmp/opencode/baseline_run_before_shaman.txt`), so this lane adds no failures.
- `tests/shaman_state.lua`: **316 checks PASS** (was 252; +64: sections 22 S2 bar, 23 S3 hold + wash + mode-switch pin, 24 S4 choice/guard/gather, 25 RB badge, 26 S5 tint; shield fallback pin updated).
- `tests/weave_state.lua`: **357 checks PASS** (was 298; +59: new pure helpers + updated 3-charge fallback pins).
- `luacheck .`: **0 errors**, 45 warnings / 71 files — the 4 touched files contribute **0 warnings** (`luacheck weave.lua classes/shaman.lua tests/weave_state.lua tests/shaman_state.lua` → 0/0).
- Mutation proofs on `/tmp/opencode/mut_shaman/` (full copy; final code; restored and verified byte-identical after each — `diff -q` clean; log `/tmp/opencode/final_mutation_proofs_shaman.txt`):
  1. **S4 rune/talent gate bypassed** (`weave.lua get_mw5_spender`: `lava_burst_known ~= true` → `false`): weave_state **4 FAILs**, shaman_state **1 FAIL** ("without the rune the MW5 marker stays Lightning Bolt"). Restored.
  2. **FS-collision guard shock leg removed** (`weave.lua should_hold_mw5`: `and shock_ready == true` → `and true`): weave_state **2 FAILs**, shaman_state **2 FAILs** (marker + gather gate). Restored.
  3. **Badge mode-switch text refresh removed** (`classes/shaman.lua`: drop `self.weave_ss_seconds = nil`): shaman_state **1 FAIL** ("a running cooldown keeps the cooldown text", got `SS HOLD`). Restored.
  The copy's full harness after restore: 35 steps / 2 failed — identical to the repo.
- Two weak checks were found by the proofs and tightened (recorded so the next desk trusts the pins): the rune-gate assertion was masked by the FS guard (fixed by clearing the FS fixture first), and the mode-switch text pin was reset by `post_init` in section 20 (fixed by priming the whole-second cache).

## 4. UNCONFIRMED items

- **UNCONFIRMED:** S4 guard semantics in-client — the exact WeakAura behavior behind "FS-collision guard (don't overwrite FS <2s remaining)" was not source-verifiable (Reddit source is login-walled; only the bench summary and the brainstorm bank text were available). Implemented literally as "hold weave if FS < 2s and shock ready"; confirm the feel in-client.
- **UNCONFIRMED:** Rockbiter rank ids above 8017 — name-only matching until confirmed in-client (the 8017 id itself is reference-sourced, not client-verified).
- **UNCONFIRMED:** Stormstrike trigger id 32175 as a target-aura id (accepted defensively; the debuff id 17364 is CONFIRMED).
- **UNCONFIRMED:** in-client behavior of every new visual (S2 bar placement above the FS bar, wash geometry on non-3 s swings, RB badge) and the lazy-creation timing — the offline harness cannot load the addon.
- **UNCONFIRMED:** the 4th Lightning Shield slot (era/talent variants) and the corrected unreadable-count fallback feel; the 3-charge fallback is reference-cited, the 4-slot row is repo history.
- Deferred/optional (one line each): bank S2's optional guide rule "withhold LB-weave until SS debuff up" needs the frozen engine — not built; bank S3's twist-impossible tint pattern was read as the final-fraction wash (built); SoD Rolling Thunder / LvB-under-SS-debuff modelling stays with the engine lane.

Bench rule honoured: nothing overwritten; this is the shaman lane's single report file. Cross-references: `desks/shaman/journal.md` (2026-10-17 build-out entry), `desks/shaman/.signals/20261017T142715Z.json`, `bench/briefs/brief_shaman_2026-10-17.md`, `bench/verify_bank.md` S2-S5 rows + §4.3 correction, `bench/discover_features.md` #6/#7, `/tmp/opencode/brainstorm_bank.md` S3/S4 originals, `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_ClassMods.lua` (4217, 4141-4144, 3514).
