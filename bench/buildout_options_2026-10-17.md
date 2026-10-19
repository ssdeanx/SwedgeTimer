# buildout options — every round toggle wired (round close-out)

Date: 2026-10-17. Desk: options. Brief: `bench/briefs/brief_options_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").

## 1. Scope + files changed

Writable scope held exactly: `option_tables.lua`, `config_presets.lua`, `config.lua`,
`tests/options_load_state.lua`. `option_table_presets.lua` was NOT needed (no preset in this
pass's set; left untouched). No other file touched; no git ops; no lint-config change; no `_`
renames; no unused-variable work. Line endings preserved (`config.lua` / `config_presets.lua`
stay CRLF, `option_tables.lua` / the suite stay LF — verified with `file(1)` after the edits).

- `option_tables.lua` — 27 new toggle widgets (§2), plus one factual copy fix: the druid HUD
  copy still said "No druid icon ever glows, so this toggle has no effect on this class" while
  D2's Tiger's Fury / Berserk slots now glow through `hud_glow_enabled` (`classes/druid.lua:1943`,
  `hud.lua:899`); the `hud_desc`/`glow_desc` strings now say TF/Berserk glow in combat once ready.
  Includes the shaman-weave round-2 addendum toggles, which landed mid-pass and were wired
  immediately (rows 26/27; the addendum report was read before wiring).
- `config_presets.lua` — `ST.DRUID.defaults` gains `hud_show_tf = true` and
  `hud_show_berserk = true` (hide-on-false shape like every sibling slot toggle — see §3).
- `config.lua` — `ST.defaults.profile` gains `diag_tick_counters = false` and
  `enemy_swing_enabled = false` (the two reports' documented defaults).
- `tests/options_load_state.lua` — druid §4 slot list gains `tf`/`berserk`; new §6 pins every
  wired toggle (widget presence, get/set resolution, getter reads the exact key, default source).

No class-module code touched; no key renamed; no existing key's shipped default changed
(`show_warrior_rampage_badge` was already wired at `true` — verified present, untouched).

## 2. The toggle table (key → widget group → default → source report)

Default column = the shipped state after this pass. "nil = OFF" means the key is absent from
the defaults and every consumer reads it nil-safely (`== true` enables).

| # | Key | Widget group (panel, order) | Type | Shipped default | Source report |
|---|---|---|---|---|---|
| 1 | `diag_tick_counters` | Top level, 1.31 | toggle | `false` (config.lua) | buildout_diag §2 |
| 2 | `enemy_swing_enabled` | Top level, 1.32 | toggle | `false` (config.lua) | buildout_enemy-swing §"Option defaults" |
| 3 | `design_mouse_anchor` | Design Mode, 1.55 | toggle | nil = OFF | buildout_bars-design §2 |
| 4 | `aow_exo_pulse_enabled` | PALADIN > Art of War Procs, 2.22 | toggle | nil = OFF | buildout_paladin §2 |
| 5 | `jotc_bar_enabled` | PALADIN > Judgement & Cooldowns, 2.72 | toggle | nil = OFF | buildout_paladin §2 |
| 6 | `cd_icons_enabled` | PALADIN > Judgement & Cooldowns, 2.73 | toggle | nil = OFF | buildout_paladin §2 |
| 7 | `twist_score_enabled` | PALADIN > Seal Twisting, 3.41 | toggle | nil = OFF | buildout_paladin §2 |
| 8 | `twist_score_persist` | PALADIN > Seal Twisting, 3.42 (disabled while 7 off) | toggle | nil = OFF | buildout_paladin §2 |
| 9 | `twist_lust_override_enabled` | PALADIN > Seal Twisting, 3.43 | toggle | nil = OFF | buildout_paladin §2 |
| 10 | `show_warrior_bank_cue` | WARRIOR > Warrior Trackers, 3.16 | toggle | nil = OFF | buildout_warrior §3 |
| 11 | `show_warrior_battle_shout_badge` | WARRIOR > Warrior Trackers, 3.17 | toggle | nil = OFF | buildout_warrior §3 |
| 12 | `hunter_cast_zone_enabled` | HUNTER > Hunter Cast Bar, 3.4 | toggle | nil = OFF | buildout_hunter §4 |
| 13 | `hunter_bw_badge_enabled` | HUNTER > Pet Badges, 6.52 | toggle | nil = OFF | buildout_hunter §4 |
| 14 | `hunter_frenzy_stacks_enabled` | HUNTER > Pet Badges, 6.53 | toggle | nil = OFF | buildout_hunter §4 |
| 15 | `hunter_multi_target` | HUNTER > Next Action Guide, 7.2 | toggle | nil = OFF | buildout_hunter §3/§4 (H3) |
| 16 | `show_shaman_stormstrike_bar` | SHAMAN > Shaman Trackers, 2.6 | toggle | nil = OFF | buildout_shaman §2 (S2) |
| 17 | `show_shaman_wf_hold_tint` | SHAMAN > Shaman Trackers, 2.7 | toggle | nil = OFF | buildout_shaman §2 (S3) |
| 18 | `show_shaman_rockbiter_badge` | SHAMAN > Shaman Trackers, 2.8 | toggle | nil = OFF | buildout_shaman §2 (RB) |
| 19 | `show_druid_pips` | DRUID > Druid Trackers, 13.11 | toggle | nil = OFF | buildout_druid §5 (D3) |
| 20 | `show_druid_shred_countdown` | DRUID > Druid Trackers, 13.12 | toggle | nil = OFF | buildout_druid §5 (D5) |
| 21 | `show_druid_maul_badge` | DRUID > Druid Trackers, 13.13 | toggle | nil = OFF | buildout_druid §5 (D6) |
| 22 | `show_druid_omen_glow` | DRUID > Druid Trackers, 13.14 | toggle | nil = OFF | buildout_druid §5 (Omen) |
| 23 | `show_druid_gcd_tick` | DRUID > Druid Trackers, 13.15 | toggle | nil = OFF | buildout_druid §5 (GCD tick) |
| 24 | `hud_show_tf` | DRUID > Cooldown HUD > Icons (8.4x) | toggle | `true` (hide-on-false — §3) | buildout_druid §5 (D2) |
| 25 | `hud_show_berserk` | DRUID > Cooldown HUD > Icons (8.4x) | toggle | `true` (hide-on-false — §3) | buildout_druid §5 (D2) |
| 26 | `show_shaman_spell_positions` | SHAMAN > Shaman Trackers, 2.9 | toggle | nil = OFF | buildout_shaman-weave §4 (round-2 addendum) |
| 27 | `show_shaman_dw_sync` | SHAMAN > Shaman Trackers, 2.91 | toggle | nil = OFF | buildout_shaman-weave §4 (round-2 addendum) |

Already-wired row re-verified, no change: `show_warrior_rampage_badge` (WARRIOR > Warrior
Trackers 3.15, default `true`, `== false` hides — buildout_warrior §3).

Widget details: all rows use the class getter/setter (`get = "getter"` / `set = "setter"`),
except `design_mouse_anchor` (inline functions like its Design Mode siblings) and the two
profile rows (the top-level global getter/setter, like `welcome_message`). Descriptions are
one-liners derived from each report's wording (e.g. H3 uses the report's exact tooltip; the
diag row documents the next-login/reload semantics per buildout_diag §5). New headers added:
PALADIN "Judgement & Cooldowns" (2.7), HUNTER "Pet Badges" (6.5) — the two groups the reports
imply but never named; no existing header/description changed except the druid glow copy (§1).

Consumer correspondence (the widget must read the same key the class code reads) was verified
by source inspection per row, e.g. `classes/shaman.lua:1289` `show_shaman_stormstrike_bar == true`,
`:1703` `show_shaman_spell_positions == true`, `:1832` `show_shaman_dw_sync ~= true`;
`hunter_ui.lua:687` `hunter_cast_zone_enabled ~= true` (`:1015/1016` the pet badges);
`classes/warrior.lua:1782/1819`; `classes/paladin.lua:1250/163/1940/1007/472/2133`;
`classes/druid.lua:1233-1237` + `hud.lua:611` (`hud_show_*` `== false` hides);
`designmode.lua:404/464`; `diag.lua:205`; `enemy_swing.lua:248`.

## 3. Defaults shipped (and the two shape exceptions)

- Policy: every `== true`-read key ships nil/absent = OFF — **no default-visible change**, as
  the brief requires. The reports' "recommended/intended default true" values (hunter cast
  zone/badges, shaman S2/S3/RB + the round-2 addendum pair, druid §5 five) are deliberately
  NOT enabled in this pass: all are explicitly owner-gated on in-client verification, and
  shipping them true would surface new widgets on untouched profiles. They remain a one-line
  change for the owner's later call.
- `hud_show_tf` / `hud_show_berserk` are the hide-on-false shape (`hud.lua:611` reads
  `db[icon.show_key] == false`), so nil already means "shown"; shipping `true` (buildout_druid
  §5 recommended default, "mirrors the other slot toggles") changes no behaviour and makes the
  options checkbox match the effective default. They are gated by `hud_enabled` (default
  false), so nothing surfaces until the HUD master is on. Pinned true in the suite (§4).
- `diag_tick_counters = false` and `enemy_swing_enabled = false` are the two reports' explicit
  "add to defaults" instructions; false = off = identical behaviour to absent.

## 4. Tests

`tests/options_load_state.lua` → **521 checks, 0 failed** (was green before; new §6 adds the
pass's checks):

- §4 druid slot list gains `tf`/`berserk`, so the standing three-way parity checks now cover
  the two D2 slots (module declares the key; `hud_show_<slot> = true` ships; a toggle widget
  exists; orders unique in the ≥8.0 range).
- §6 new: for each of the 27 wired toggles — the widget exists with `type = "toggle"` in the
  right panel, carries a numeric order, its `get`/`set` resolve through the panel handler (or
  are inline functions), and its getter reads the exact class/profile key (`true` → true,
  nil/`false` → falsy). Defaults-source checks: every nil-off key must NOT ship `= true` in its
  class defaults block (or in `ST.class_defaults` for `design_mouse_anchor`, or `config.lua`
  for the two profile keys), and the two hide-on-false keys must ship `= true`. A wired default
  flipped to ON fails exactly here (mutation M1).

## 5. Evidence

- `bash tests/run.sh` (repo, final state, AFTER the shaman-weave round-2 landing + the addendum
  wiring): **35 steps, 2 failed** — failure set byte-identical to the shaman-weave lane's
  round-2 final baseline (`/tmp/opencode/r2_final_repo.txt` vs
  `/tmp/opencode/options_final_run2.txt`, `diff` clean): `bars_state` and `hud_state`, the final
  reconcile wave (frame/slot count rows) — untouched per the brief. Every other step green,
  including `options_load_state`, `main_init_state`, `wiring_check`, `toc_check`. The earlier
  post-edit run before the addendum (`/tmp/opencode/options_final_run.txt`) had the same
  2-row failure set as its pre-edit baseline.
- `lua5.1 tests/options_load_state.lua`: 521 checks / 0 failed; walk totals 2300 widgets /
  240 groups / 3953 orders across the 9 classes (floors 800/100/1000 hold).
- `luacheck .`: **0 errors**, 45 warnings / 71 files — identical to the pre-edit baseline
  (warning set compared category-by-category against pre-edit copies of the file in
  `/tmp/opencode/mut_paladin|mut_hunter|mut_shaman|mut_warrior`: same 8 categories, line
  numbers shifted only). Current option_tables lines: 6, 51, 96, 493, 680, 686, 4397, 4656 —
  all pre-existing.
- Order-collision scan (all orders, whole tree; `/tmp/opencode/orders_check/` copy with the
  suite's walker extended to flag every duplicate order value): only the two pre-existing
  families — the shared `gcd1a/gcd1b_marker_fractional_height` 1.6 pair in the GCD-marker
  preset (every hand panel) and the documented warrior 3.1/3.10 pair. **No duplicate involves
  any widget added by this pass.**
- **Mutation proofs on `/tmp/opencode/mut_options/`** (full copy of the FINAL tree; each
  mutation applied, checked, restored — `cmp` confirms all four touched files byte-identical
  to the repo after restores; log `/tmp/opencode/mut_options_run_m1b.txt`):
  1. **Default flip to ON** — `show_shaman_spell_positions = true` added to the SHAMAN
     defaults block (the exact "default-visible change" the brief forbids): `options_load_state`
     → **1 FAIL** ("Shaman: show_shaman_spell_positions does NOT ship a true default (nil =
     off)"). Full harness on the mutated copy → **35 steps, 3 failed** = the 2 known reconcile
     rows + `options_load_state`; i.e. the new check is the one that catches it. Restored →
     521/0.
  2. **Widget removal** — the `show_shaman_dw_sync` widget deleted from the SHAMAN panel:
     `options_load_state` → **1 FAIL** ("Shaman: show_shaman_dw_sync has a toggle widget (got
     nil)") and the check count drops 521 → 515 (the widget's six checks skip). Restored → 521/0.
  (An earlier pair of proofs on the pre-addendum tree — default flip on
  `show_shaman_stormstrike_bar`, widget removal of `show_druid_pips` — behaved identically;
  logs `/tmp/opencode/mut_options_run_m1.txt`.)
- Baseline captures before any edit: `bash tests/run.sh` → 35 steps, 2 failed (same two rows);
  luacheck 45/0.

## 6. Gaps (documented, NOT wired)

| Item | Why not wired | Follow-up |
|---|---|---|
| `druid_pips_x` / `druid_pips_y` + save/reset seam (buildout_druid §5/§6) | Not a toggle; the consumer is the pips design target's `save`/`reset` override (the factory in `bars.lua`, or the druid call site in `classes/druid.lua`) — both outside this pass's writable scope. A position input with no consumer would be a dead widget. | The lane that owns `bars.lua`/`classes/druid.lua` wires `opts.design.save/reset` to the keys; then the two input widgets can join DRUID > Druid Trackers. |
| `practice_aw_includes_pot` / `practice_aw_includes_sob` (buildout_practice §5) | The practice report defers them ("deferred option needs for a later pass"); the engine and UI both skip them today (`practice.lua:737-738`, `practice_ui.lua:68`). | Wire when the P5 AW-combo drill lands in `practice_ui.lua`. |
| `/st diag reset` verb (buildout_diag §5) | Not a toggle; a slash command lives in `main.lua` (out of scope). | Optional later pass. |
| ~~Shaman-weave addendum~~ | **Landed mid-pass** (`bench/buildout_shaman-weave_2026-10-17.md` §4, signal 14:46:17Z): both keys (`show_shaman_spell_positions` read at `classes/shaman.lua:1703`, `show_shaman_dw_sync` at `1832`) are wired as rows 26/27 and pinned in the suite. Round-1 S4 adds no key (rides `weave_mw_enabled`). | None — closed. |
| `hunter_multi_target` consumer | Wired per the H3 spec (report §3: "the toggle alone is the H3 definition"), but the gather/engine that reads `inputs.multi_target` is a future round — the key is inert until then. Deliberate, documented. | H3 engine round consumes `db.hunter_multi_target`. |
| No-toggle lanes | compat-bl §6 (no user-visible toggles), practice §5 ("adds no toggles and no options"), bars-design pips (no user toggle of its own), warrior W2 gate/W7 probe (not toggles), shaman shield-fallback correction (behaviour under the existing `show_shaman_shield_charges`). | Nothing to wire. |

## 7. UNCONFIRMED (in-client list)

- The rendered options pages (widget placement/order/disabled states, the two new headers) were
  never opened in a client — the offline suite pins the tree, not the pixels. Owner's test
  session: open the class panels and confirm each new toggle appears in its documented group.
- `hud_show_tf` / `hud_show_berserk` shipping true is a presentation choice only (nil behaves
  identically); confirm the HUD icons row still reads as expected with the HUD master on.
- The recommended-true defaults (hunter / shaman round-1 + round-2 / druid) remain OFF pending
  the owner's in-client verification of those widgets — flipping them is a one-line, gated
  change per report.
- No git operations performed; the tree is left with all changes in place and stated.
