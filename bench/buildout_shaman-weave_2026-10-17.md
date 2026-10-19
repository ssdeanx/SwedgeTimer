# buildout_shaman-weave — round 2: 2-3 stack MW weave + spell-position markers + Flurry ICD sync

Date: 2026-10-17. Desk: shaman. Brief: `bench/briefs/brief_shaman-weave_2026-10-17.md` (operator directive, verbatim spec carried there).
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").
Refines S4's trigger; the LvB rune/talent gate stays. S1 totem twist still BLOCKED/untouched.

## 1. Marker math spec (what the row computes, pure side in `weave.lua`)

For every shown weave spell on the current mainhand swing:

- `effective = base_cast / haste × MW_mult(stacks)` — existing `st.weave.get_effective_cast_time` via `ST.SHAMAN.get_weave_effective_cast_time` (MW multiplier from the live stack count; 0 at 5 stacks).
- `latest_safe_start = clamp((swing_duration − effective − latency) / swing_duration)` — existing `st.weave.get_marker_fraction`. This is where the cast must START so it lands just before the MH swing.
- `now_fraction = clamp((now − swing_start) / swing_duration)`.
- State (`st.weave.get_spell_position_state`, weave.lua:130): `"wait"` (stacks < `MW_MIN_WEAVE_STACKS = 2`, weave.lua:128, or an unreadable/NaN reading — unknown never reads ready); `"ready"` (stacks ≥ 5 short-circuit, or `now_fraction ≤ latest_safe_start`); `"clip"` (`now_fraction > latest_safe_start` — casting now overruns the swing). `can_prompt_weave` (weave.lua:152) is the one-call prompt gate: ready only; **a clip is never prompted**.
- Zone (`st.weave.get_cast_zone_bounds`, weave.lua:227): `min`/`max` of the numeric latest-safe-starts across the shown spells; the band draws only when `max > min` (a degenerate single-start zone hides).
- Icon x = `latest_safe_start × bar_width`; the cast-time number is `%.1f` of `effective`; the zone band spans `[min, max]`; the label is centred over the band.
- Everything is recomputed on every mainhand tick from the live swing/stacks/haste, so every swing rollover, LB/CL cast, SUCCEEDED and aura change re-adjusts the row (the operator's "after each swing, lb, cl and rest should update and readjust").
- Geometry (all constants at classes/shaman.lua:257-277, the follow-up refinement hook): band at y 18..32 above the bar (clear of Flame Shock +2..8 and Stormstrike +10..16), icons 14 px centred at y 25, numbers to the right of each icon, label at y 34. Widgets: zone band + label + 3 icons + 3 numbers (lazy, option-gated).

## 2. Screenshots-to-model mapping (from the brief's descriptions; example link still pending)

| Operator's screenshot element | Built as |
|---|---|
| Swing bar with OH/MH labels and white sweep | Existing MH/OH bars + the offhand spark mirror (untouched); the row draws through the existing class hook on the MH visuals frame only |
| Bracket above the bar labeled "Spells start cast range zone" | `vf.weave_pos_zone` translucent band + `vf.weave_pos_label` (caption is the literal string) |
| Blue spell icons (LB, CL) positioned inside the zone ahead of the MH marker | One icon per spell at its own latest safe start inside the band, tinted with the weave family colour (LB light blue, CL dark blue; LvB lava orange when known) |
| Cast-time numbers (2.4 / 1.9) shown | `vf.weave_pos_times[key]`, `%.1f` of the effective (haste/MW-adjusted) cast time |
| Frame showing the clipping case where a cast extends past the MH swing | Per-spell clip state: icon + number turn red once the safe start has passed; a live clipped cast keeps the existing red spark |

## 3. Changes

Writable scope held exactly: `weave.lua`, `classes/shaman.lua`, `tests/weave_state.lua`, `tests/shaman_state.lua`. No other file touched (bars_state deliberately not edited); no git ops.

### weave.lua (pure, WoW-free)
- 2-3 stack trigger: `MW_MIN_WEAVE_STACKS = 2`, `get_spell_position_state` (ready/wait/clip, NaN-safe), `can_prompt_weave`.
- Zone: `get_cast_zone_bounds(starts)` → min/max/numeric count.
- ICD registry (the operator's "knowing icd's"): `ICD_SECONDS = { windfury = 3, flurry = 0.5 }` (weave.lua:328) + generic `get_icd_remaining(last_time, icd_seconds, now)` (weave.lua:338); `get_windfury_icd_remaining` now delegates to it (identical behaviour, existing pins pass); `get_flurry_icd_remaining` (weave.lua:353).
- DW sync: `DW_SYNC_THRESHOLD_SECONDS = ICD_SECONDS.flurry` (the model where the ICD affects timing; weave.lua:360), `get_dw_sync_offset(mh_ends_at, oh_ends_at)`, `is_dw_desynced(offset)` (strict `>`, nil never warns).

### classes/shaman.lua
- Flurry data (`WEAVE_FLURRY_IDS = { [16280] }` + name fallback; reference SuperSwingTimer_ClassMods.lua:4221) read in the merged aura walk (classes/shaman.lua:482); `on_aura_change` stamps `weave_flurry_proc_at` on a stack-count INCREASE (a fresh proc; a decrease is a consumed charge) and stores the count.
- `update_spell_positions` (classes/shaman.lua:1702): lazy zone/label/icons/numbers, per-slot entry resolution (LB/CL from the catalogue honouring `weave_families`; LvB via `resolve_lava_burst` + the S4 known gate), state colours (family / red clip / dim wait), zone band + centred label. Per-tick caches for the icon texture and the cast-time value (no string/SetTexture churn on a stable swing).
- `update_dw_badges` (classes/shaman.lua:1831): "DW SYNC 0.1s" (green) / "DW DESYNC 0.8s" (amber) from the MH/OH landings vs the 0.5 s Flurry ICD threshold, hidden without a live offhand or known landings; "FL n [icd]" ice-blue readout with the live 0.5 s proc countdown. Both stacked under the Rockbiter badge (y −28 / −38).
- `on_bar_update` wires both after the existing trackers (classes/shaman.lua:2016-2017); swing-activity gates only — no `st.is_mainline` gate anywhere.
- The frozen guide engine's MW5-only weave rule is untouched: the 2-3 stack prompt is the assist row (option-gated), so the guide's label and icon can never disagree with it.

## 4. Option defaults (standing-rule record for the options pass)

| Key | Shipped this round | Intended default (options pass) |
|---|---|---|
| `show_shaman_spell_positions` | absent; read `== true` → **nil = off** | true (the operator's core visual) |
| `show_shaman_dw_sync` | absent; read `== true` → **nil = off** | true (DW sync + Flurry readout) |

No default-visible change in any client this round (both toggles absent from config_presets; widgets exist only after the toggle is on).

## 5. Bar-count deltas (for the final reconcile wave)

Construction-time counts unchanged: every new widget is created lazily on the first live tick with its option ON, and bars_state runs with both options nil → **SHAMAN construction counts stay 13 textures + 3 fontstrings (MH) and the bars_state SHAMAN checks stay green** (verified: bars_state's check-level failure set is byte-identical to the pre-edit baseline).

When enabled, the SHAMAN mainhand visuals frame gains:
- `show_shaman_spell_positions` on: **+4 textures** (zone band + 3 spell icons) and **+4 fontstrings** (zone label + 3 cast-time numbers).
- `show_shaman_dw_sync` on: **+2 fontstrings** (sync readout + Flurry readout).
- Both on: **+4 textures / +6 fontstrings**.

## 6. Evidence

- `bash tests/run.sh` (in-repo, final state): **35 steps, 2 failed** — `bars_state.lua` and `hud_state.lua`, the known final-reconcile-wave steps (paladin/warrior/hunter/druid counts + druid HUD slots). Check-level failure sets are **byte-identical to the pre-edit baseline captured this round** (`/tmp/opencode/baseline_r2_shaman.txt` vs `/tmp/opencode/r2_final_repo.txt`), i.e. this lane adds zero failures; zero shaman failures in either suite.
- `tests/weave_state.lua`: **417 checks PASS** (was 357; +60: position-state matrix incl. NaN, prompt gate, zone bounds, ICD registry/generic read, Flurry ICD, DW sync offset/threshold).
- `tests/shaman_state.lua`: **378 checks PASS** (was 316; +62: section 27 spell-position row — creation gating, positions/cast times, ready/clip/wait colours, LvB join, 5-stack instant + degenerate zone, rollover re-adjust; section 28 DW/Flurry badges — sync/desync/threshold boundary, unknown landings, Flurry stacks/ICD countdown/restamp rules).
- `luacheck`: **0 errors**; the 4 touched files contribute **0 warnings** (repo total unchanged at 45 warnings / 71 files).
- Mutation proofs on `/tmp/opencode/mut_shaman_r2/` (full copy; restored and verified byte-identical after each; log `/tmp/opencode/r2_mutation_proofs.txt`):
  1. **Clip guard removed** (`get_spell_position_state`: `return "clip"` → `return "ready"`): weave_state **2 FAILs**, shaman_state **3 FAILs** (the red-tint assertions).
  2. **2-3 stack gate raised to 5** (`mw_stacks < MW_MIN_WEAVE_STACKS` → `< MW_MAX_STACKS`): weave_state **4 FAILs**, shaman_state **5 FAILs** (ready colours/alpha).
  3. **Flurry ICD zeroed** (`ICD_SECONDS.flurry = 0.5` → `0`): weave_state **5 FAILs**, shaman_state **6 FAILs** (ICD readouts, sync threshold).
  The copy's full harness after restore: 35 steps / 2 failed — identical to the repo.

## 7. UNCONFIRMED items

- **UNCONFIRMED:** the Flurry 0.5 s ICD value and the sync-threshold=ICD model — operator-provided ("flurry has .5 sec icd"); no primary source found; the read-only reference only tracks Flurry as a buff icon (no ICD or sync logic). Confirm in-client and refine against the operator's example link.
- **UNCONFIRMED:** Flurry id 16280 — reference-sourced (SuperSwingTimer_ClassMods.lua:4221), not client-verified; ranks match by name only.
- **UNCONFIRMED:** the visual layout vs the operator's reference screenshots (band/icon/label geometry, icon size, number placement) — the example link is pending; every constant is grouped at the top of the position-row section for the follow-up.
- **UNCONFIRMED:** in-client feel of the 2-3 stack states and the clip timing at real weapon speeds/haste; the offline harness cannot load the addon.
- **UNCONFIRMED:** whether the position row should also cover the healer families (HW/LHW/CH) — built for LB/CL (+LvB) per the brief's enumeration; hook noted in the code comment.
- Refinement notes (one line each): at 5 stacks the instant spells share the swing-end position (icons overlap, degenerate zone hidden); the position row and the existing breakpoint marker draw together (small marker over the 14 px icon) — the follow-up can merge or offset them.

Bench rule honoured: nothing overwritten; this is the shaman weave lane's single report file. Cross-references: `desks/shaman/journal.md` (2026-10-17 weave round 2 entry), `desks/shaman/.signals/20261017T144617Z.json`, `bench/briefs/brief_shaman-weave_2026-10-17.md`, `bench/buildout_shaman_2026-10-17.md` (round 1), `bench/verify_bank.md` S4 row, `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_ClassMods.lua` (4221).
