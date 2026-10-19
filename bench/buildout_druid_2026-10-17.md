# buildout_druid — D2 TF/Berserk HUD slots, D3 pips wiring, D4 EMA TTD, D5 countdown, D6 Maul badge, Omen glow, GCD tick overlay (build-out round 1)

Date: 2026-10-17. Desk: druid. Brief: `bench/briefs/brief_druid_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").

Scope honoured: `classes/druid.lua`, `druid_energy.lua`, `druid_guide.lua`,
`tests/druid_state.lua`, `tests/druid_energy_state.lua`, `tests/druid_guide_state.lua`.
Nothing else was touched (no tocs, no bars.lua, no hud.lua, no config_presets.lua,
no lint config). No git was run. D1 stays BLOCKED (untouched; the reserved
plug-in remains documented in `gather_guide_inputs`).

## 1. Changes

### druid_energy.lua (pure, WoW-free)
- `ENERGY_TICK_GAIN = 20` (the flat tick grant; the 19-22 window stays the detection bracket).
- D4 constants: `TTD_EMA_ALPHA = 0.25`, `TTD_SAMPLE_SECONDS = 0.25`.
- `update_hp_velocity(ema, hp, prev_hp, dt, alpha)` — one EMA step of HP/s; heals
  clamp to zero velocity; NaN/unreadable/zero-dt samples return nil (the caller
  re-seeds); alpha falls back to the shipped constant.
- `get_time_to_die(hp, hp_velocity)` — `hp / velocity` while the velocity is a
  positive number; anything unreadable/NaN reads nil.
- `get_time_to_energy_cost(anchor, now, energy, cost, cycle, gain)` — the D5
  countdown maths (ceil ticks, next tick boundary + full cycles; 0 when affordable;
  nil when unknown/NaN).
- `get_gcd_tick_fraction(anchor, now, gcd_remaining, cycle)` — the discover-#4
  marker fraction (cycle fraction + GCD share, clamped; nil when no GCD/unknown).

### classes/druid.lua
- **D2 TF/Berserk HUD slots**: two descriptors appended before the trinkets
  (`tf` fallback id 9845, `berserk` 50334); `druid_tf_ids` gains 50213;
  `ST.DRUID.resolve_hud_slot_icons()` (called from post_init) re-points the icons
  at the client's current rank. `get_hud_state` hides each slot where the client's
  spell data has no such spell (rank ids first, then the literal English name;
  positives latch, negatives retry at the 5 s cadence; Berserk additionally rides
  the `sod_runes_present()` basis on the ERA token). Both slots read cooldowns by
  the client's own localized name (rank-agnostic — the brief's correction) and glow
  while ready in combat (the paladin wings rule); both join `HUD_SKIP_GCD` (off-GCD
  abilities — UNCONFIRMED) and the fallback table.
- **D3 pips wiring**: `create_pips_widget` calls the installed
  `ST:new_pips(parent, opts)` (colon shape, confirmed against `bars.lua` and
  `bench/buildout_bars-design_2026-10-17.md` §1/§5 — the buildout landed while this
  lane ran; the earlier probe list was pruned to the confirmed path), pcall-guarded.
  Construction opts: `point = "BOTTOMLEFT", x = 0, y = -18` (clear of the centred
  D5/D6 readout; the factory's generic design reset re-anchors here) and
  `design = { key = "druid_pips", title = "Combo Points" }` (the persisted save
  seam needs db keys the options pass owns — session-only drop until then).
  `update_druid_pips` drives `set(0-5)` + `glow_full(count >= 5)` from the cat
  combo power; hides outside cat form or on an unreadable count.
- **D4 TTD**: `sample_target_time_to_die(self, now)` in `gather_guide_inputs`
  replaces the hard nil `inputs.time_to_die`; state on the module instance
  (target GUID, last hp + stamp, EMA). `target_short_lived` and `can_powershift`
  keep their frozen nil shapes.
- **D5 countdown**: `update_druid_shred_countdown` + text below the bar
  ("Shred in Xs", ceil seconds). Cost: TBC 42 (the guide's `SHRED_COST_TBC`) and
  Wrath 42 (UNCONFIRMED); no verified cost on any other family, so no countdown
  there. The tick sampler's new `sample` flag keeps the cycle anchor alive while
  the countdown is on and the tick bar is off.
- **D6 Maul badge**: `sample_maul_badge` on `on_rage_update` (bear-only by the
  RAGE dispatch) tracks the at-cap segment and capped-gain events per fight;
  `update_druid_maul_badge` shows `"Cap Ns"` in bear form; combat exit flushes and
  resets. No rage units are claimed — the event stream reports post-change values
  only, so per-gain magnitudes are unobservable (documented in the code).
- **Omen glow (discover #8)**: `update_druid_omen_glow` lights a halo around the
  energy column while the guarded 16870 proc is found; the player scan now also
  runs when only the glow toggle is on (and still reads nothing when guide + glow
  are off).
- **GCD tick overlay (discover #4)**: `update_druid_gcd_tick` repositions a 1 px
  marker on the energy column at the pure fraction (only with the column visible).
- `post_init` initialises the new D4/D6 state and calls the HUD icon resolver;
  `on_combat_exit` resets the badge; the header comment documents the round.

### druid_guide.lua (annotations only — integration points intact)
- The `time_to_die` frozen-input note and the WRATH appendix now name the D4 EMA
  sampler as the source (the nil = unknown shape and every rule are unchanged).

### Tests (never weakened)
- `tests/druid_energy_state.lua`: +73 checks (63 -> **136**) — constants, the EMA
  step (seed/smoothing/heal/spike-damping/fallbacks/NaN), the TTD estimate, the
  countdown maths (boundaries/ceil/fallbacks/NaN) and the GCD fraction.
- `tests/druid_state.lua`: +90 checks (325 -> **415**) — pips (factory shape,
  opts, drive, gates, no-factory, throwing-factory), countdown (TBC/WRATH/Era
  cost gates, reads, ceilings), badge (segment/events/reset/no-reads), omen glow,
  GCD marker, D2 slots (list/re-point/liveness/retry/latch/Era-rune/provider glow).
  The fixture gained `GetSpellCooldown` and player-aura stubs (defaults identical
  to the previous fallbacks) and `player_auras`.
- `tests/druid_guide_state.lua`: +17 checks (65740 -> **65757**) — the fixture
  gained UnitHealth/UnitGUID stubs (defaults nil = the old "no readable target"
  shape); section 16 pins the D4 timeline (seed/throttle/steady/heal/target
  switch/death/unreadable/stale clear) and the end-to-end Wrath W8 Bite driven by
  the estimate. The two section-8 labels now say "no readable target health".

## 2. Evidence

- `lua5.1 tests/druid_energy_state.lua`: **PASS, 136 checks**.
- `lua5.1 tests/druid_state.lua`: **PASS, 415 checks**.
- `lua5.1 tests/druid_guide_state.lua`: **PASS, 65757 checks** (never weakened).
- `luacheck .`: **0 errors**; tree total 45 warnings / 71 files (same count as the
  pre-round baseline — this lane adds no warnings; `classes/druid.lua` carries its
  2 pre-existing whitespace warnings, `druid_energy.lua` and the three suites 0).
- `bash tests/run.sh`: **35 steps, 2 failed — neither is a functional failure; both
  are shared-suite descriptor/count rows awaiting the round's reconcile pass**:
  - `tests/hud_state.lua` (401 checks, 4 failed, all §15 druid): `#slots` 8 -> 10,
    slot order gains `tf`, `berserk` before the trinkets, `#icons` 8 -> 10, frame
    width `6*36+5*2` (226) -> `8*36+7*2` (302). The bars-design desk's report
    already attributes this row to the druid lane's HUD slots.
  - `tests/bars_state.lua` (733 checks, 12 failed; count rows only): PALADIN/
    WARRIOR/HUNTER/pre-init rows are the other class lanes'; the **DRUID** row is
    this lane — frames 6 -> 7 (+1: the pips frame), textures 14 -> 21 (+5 pips,
    +2 gcd marker/omen glow), fontstrings 7 -> 9 (+2 countdown/badge). Also
    documented by bars-design §4.
  - Every other step passes, including `smoke.lua`, `secret_guard_state.lua`,
    `options_load_state.lua`, `wiring_check.lua`, `toc_check.lua`,
    `main_init_state.lua` and `guide_contract.lua`.
- Mutation proofs on `/tmp/opencode/mut_druid/` (full copy of the FINAL tree;
  each mutation applied, checked, restored from the original, both re-verified
  green, copy removed):
  1. D4 EMA constant (`druid_energy.lua` `TTD_EMA_ALPHA = 0.25` -> `= 1`, i.e. raw
     velocity — the exact §4.1 correction violated): `druid_energy_state.lua`
     **1 FAIL** ("the TTD EMA weights the newest sample 0.25 (D4) (got 1, want
     0.25)"), `druid_guide_state.lua` **1 FAIL** ("D4: a heal decays the EMA,
     never flips it (got nil, want 6)").
  2. D2 gate (`classes/druid.lua` berserk Era clause loses
     `sod_runes_present() == true`): `druid_state.lua` **1 FAIL** ("runeless Era
     hides Berserk (not baseline there) (got nil, want true)").
  Restored: `PASS 136 / 415 / 65757`.

## 3. TF name-lookup table (D2 correction — ids are rank-dependent)

| Family | Tiger's Fury rank ids in `druid_tf_ids` | Source |
|---|---|---|
| Classic Era / SoD | 9845, 9846 | bench/verify_bank.md §2 |
| TBC | 5217, 6793, 9845, 9846 | bench/verify_bank.md §2 |
| WotLK | + 50213 (all ranks) | bench/verify_bank.md §2 |
| any other | none (literal `"Tiger's Fury"` name probe) | the name-based correction |

The cooldown read never uses an id: the guide and the HUD both query
`GetSpellCooldown(<client-localized name>)`; ids only feed the icon rank
resolution and the aura-id match. Berserk: 50334 (WotLK, CONFIRMED
bench/verify_bank.md §2); Era only via the SoD rune basis probe; TBC none.

## 4. D4 EMA parameters (BINDING correction §4.1)

- `TTD_EMA_ALPHA = 0.25` (newest-sample weight; ~4-sample horizon — own choice,
  the competitor constant is unpublished).
- `TTD_SAMPLE_SECONDS = 0.25` (minimum sample spacing; per-frame division would
  manufacture velocity noise).
- First sample per target seeds the baseline only; every later sample smooths
  `alpha * raw + (1 - alpha) * ema`; heals contribute zero velocity (never
  negative); a target switch, a death (hp <= 0), unreadable health or a NaN
  sample drops the baseline; estimate = `hp / ema` while `ema > 0`.
- Integration points intact: the estimate feeds the frozen `inputs.time_to_die`
  only (Wrath W8 `<= 10 s`, TBC T3 `<= 12 s`); `target_short_lived` and
  `can_powershift` keep their nil shapes; unknown still defaults to the long fight.

## 5. Option defaults (documented for the options pass — all nil-safe, nil = off)

| Key | Shape | Recommended default | Note |
|---|---|---|---|
| `show_druid_pips` | `== true` shows | true | D3; bars-design factory |
| `show_druid_shred_countdown` | `== true` shows | true | D5; family-gated in code (TBC/WRATH only) |
| `show_druid_maul_badge` | `== true` shows | true | D6; bear form only |
| `show_druid_omen_glow` | `== true` shows | true | discover #8; needs the tick column |
| `show_druid_gcd_tick` | `== true` shows | false | discover #4; niche |
| `hud_show_tf` | `== false` hides | true | D2; mirrors the other slot toggles |
| `hud_show_berserk` | `== false` hides | true | D2; mirrors the other slot toggles |
| `druid_pips_x` / `druid_pips_y` + save/reset seam | — | 0 / -18 | design persistence; needs the options pass |

No default-visible change ships this round: every new widget is gated on an
explicit `== true` read, and the HUD slots only surface under the existing
`hud_enabled` master (default false).

## 6. Reconcile items for the later wave (exact updates)

- `tests/hud_state.lua` §15 (druid): `#slots == 10`; expected order
  `maul, mangle, rip, rake, bite, shred, tf, berserk, trinket1, trinket2`;
  `#DHUD.icons == 10`; width `8 * 36 + 7 * 2 == 302`. (The new liveness gates and
  the provider glow are already pinned in `tests/druid_state.lua` §28.)
- `tests/bars_state.lua` DRUID count row: frames 7, textures 21, fontstrings 9
  (the deltas and their attribution are in bars-design §4).
- Options pass: the keys in §5, plus the `druid_pips` design save seam
  (persisted position) once the db keys exist.

## 7. UNCONFIRMED

- **In-client behaviour of every new widget is UNCONFIRMED** (offline checks pin
  calls, gates and maths, not pixels): pip position/fill/glow and the design reset
  anchor, countdown text readability, badge text, omen halo, marker height.
- Wrath Shred cost 42 (own knowledge; the TBC 42 is the cited 2.5.6 value);
  every other family has no countdown by design.
- TF/Berserk off-GCD status (the `HUD_SKIP_GCD` entries — a wrong entry only
  withholds a GCD swipe from a ready icon).
- Berserk on Cata/Mists/Retail resolves through the name fallback on enUS clients
  only; the SoD Berserk rune has no offline id/name proof (the slot may draw an
  empty icon on Era+runes).
- Forever's absent Tiger's Fury is beta-doc knowledge: the probe hides the slot if
  the client's data really lacks it, but this was not verified in-client.
- The D6 model deliberately claims **no rage units** (per-gain magnitudes are not
  observable from the power event stream); the badge shows at-cap seconds and the
  state also carries the capped-gain event count.
- SoD/Forever TF/Shifting Power ids and the TBC Mangle cost reflection stay as the
  guide's existing UNCONFIRMED items (untouched by this lane).
