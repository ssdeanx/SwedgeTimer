# buildout options-grade — options-file warnings wired + 27-toggle fine-tune audit

Date: 2026-10-17. Desk: options. Brief: `bench/briefs/brief_options-grade_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").

## 1. Scope + files changed

Writable scope held exactly: `config.lua`, `config_presets.lua`,
`option_table_presets.lua`, `option_tables.lua`, `tests/options_load_state.lua`.
No other file touched; no git ops; no lint-config change; no `_` renames. Line endings
preserved (`config.lua` / `config_presets.lua` / `option_table_presets.lua` stay CRLF,
`option_tables.lua` / the suite stay LF — verified with `file(1)` after the edits).

## 2. Task-A verdict table (file:line → traced purpose → verdict + evidence)

| # | Warning (luacheck 2026-10-17) | Traced purpose | Verdict | Evidence |
|---|---|---|---|---|
| 1 | `config.lua:5` unused `LSM` | LibSharedMedia handle fetched; the file only declares default tables (plain media-key strings like `bar_texture_key = "Minimalist"`). No `LSM:` call anywhere in the file. | REMOVE (one-line rationale comment left) | `grep -n "LSM" config.lua` → only the removed line + the note. Runtime resolution lives in bars.lua + option_tables.lua, which hold their own handles |
| 2 | `config.lua:8` unused `LWIN` | LibWindow handle fetched; positions in defaults are plain x/y/point/scale values. No `LWIN.` call anywhere in the file. | REMOVE (same note) | `grep -n "LWIN" config.lua` → only the note. `LWIN.RestorePosition` calls live in option_tables.lua:4337-4378 |
| 3 | `config_presets.lua:5` unused `LSM` | Same shape: defaults-only file, zero `LSM:` calls. The genuine LSM consumer for these keys is option_table_presets.lua (`values = LSM:HashTable`). | REMOVE (one-line rationale comment left) | `grep -n "LSM" config_presets.lua` → only the note |
| 4 | `option_table_presets.lua:4` unused `st` | Second chunk vararg (st utils table). Zero `st.` uses in the file and no `st.debug` trailer — the file only defines ST tables and reads LSM. | REMOVE (`local addon_name = ...`, rationale note left) | `grep -n "st\." option_table_presets.lua` → empty |
| 5 | `option_tables.lua:51` unused `print` | `st.utils.print_msg` debug alias. Only references are two commented-out lines (`-- print(color_table)`, `-- print(hand_title)`). `st` itself stays heavily used (designmode/rotation_text/practice_ui). | REMOVE (rationale note left) | `grep -n "print(" option_tables.lua` → only the two comments |
| 6 | `option_tables.lua:4397` unused `title` | `settings.title` ("Mainhand Controls") fetched but the group is named by `settings.panel_title`. No other `settings.title` reader exists; the stale `-- print(hand_title)` refs a third, nonexistent name. Wiring it (extra header/label) would add UI surface = default-visible change, forbidden. | REMOVE (rationale note left; dict `title` fields kept as inert data) | `grep -n "settings.title\|panel_title" option_tables.lua` → defs + the single `name = settings.panel_title` use. Displayed names pinned unchanged by new §7 runtime checks |
| 7 | `option_tables.lua:96` shadowing upvalue `english_class` (line 78) | Inner re-query inside `get_player_class_pretty`; every use-site MEANT the fresh call result. | WIRE (rename inner → `pretty_class`, identical behaviour) | Suite builds + getter returns live class; §7 pins exactly one `english_class` binding remains |
| 8 | `option_tables.lua:680,686` shadowing upvalue arg `self` (line 655) | First handler param misnamed `self`; bodies use `ST:` explicitly and ignore it. Sibling getters/setters (659/665) and the hunter pair (3079/3085) already use `_`. | WIRE (rename → `_`, identical behaviour) | §7 source pins; colour widgets still resolve get/set in the walk |
| 9 | Whitespace-only warnings (old 6/493/4656, now 6/494/4658) | Trailing whitespace in comments on lines this pass did not otherwise touch. | KEEP (brief rule: fix ONLY inside lines already touched) | Untouched by every edit above; line shift is purely from the added rationale notes |

Post-pass scope luacheck: **0 errors / 3 warnings** (the three KEEP-ruled whitespace lines).

## 3. Task-B fine-tune audit (toggle → widget → consumer key read → default → verdict)

Consumer reads verified by source inspection (nil-safe shape noted per row):

| # | Key | Widget (option_tables.lua) | Consumer read | Default | Verdict |
|---|---|---|---|---|---|
| 1 | `diag_tick_counters` | top-level toggle, global get/set | diag.lua:205 `~= true` gate | `false` (config.lua) | OK — profile key, off |
| 2 | `enemy_swing_enabled` | top-level toggle, global get/set | enemy_swing.lua:248 `== true` | `false` (config.lua) | OK — profile key, off |
| 3 | `design_mouse_anchor` | Design Mode, inline get/set | designmode.lua:404/464 `== true` | nil = OFF | OK |
| 4 | `aow_exo_pulse_enabled` | PALADIN AoW Procs | paladin.lua:472/1237 `== true` / `~= true` | nil = OFF | OK |
| 5 | `jotc_bar_enabled` | PALADIN Judgement & CDs | paladin.lua:1940 `== true` | nil = OFF | OK |
| 6 | `cd_icons_enabled` | PALADIN Judgement & CDs | paladin.lua:2133 `== true` | nil = OFF | OK |
| 7 | `twist_score_enabled` | PALADIN Seal Twisting | paladin.lua:1250 `== true` | nil = OFF | OK |
| 8 | `twist_score_persist` | PALADIN Seal Twisting (disabled while 7 off) | paladin.lua:163/1345/1374 `== true` | nil = OFF | OK |
| 9 | `twist_lust_override_enabled` | PALADIN Seal Twisting | paladin.lua:1007 `== true` | nil = OFF | OK |
| 10 | `show_warrior_bank_cue` | WARRIOR Trackers | warrior.lua:1782 `~= true` | nil = OFF | OK |
| 11 | `show_warrior_battle_shout_badge` | WARRIOR Trackers | warrior.lua:1819 `~= true` | nil = OFF | OK |
| 12 | `hunter_cast_zone_enabled` | HUNTER Cast Bar | hunter_ui.lua:687 `~= true` | nil = OFF | OK |
| 13 | `hunter_bw_badge_enabled` | HUNTER Pet Badges | hunter_ui.lua:1015 `== true` | nil = OFF | OK |
| 14 | `hunter_frenzy_stacks_enabled` | HUNTER Pet Badges | hunter_ui.lua:1016 `== true` | nil = OFF | OK |
| 15 | `hunter_multi_target` | HUNTER Next Action Guide | NONE (H3 engine future round) | nil = OFF | OK — deliberately inert, documented |
| 16 | `show_shaman_stormstrike_bar` | SHAMAN Trackers | shaman.lua:1289/1357 `== true` | nil = OFF | OK |
| 17 | `show_shaman_wf_hold_tint` | SHAMAN Trackers | shaman.lua:1462/1532 `== true` | nil = OFF | OK |
| 18 | `show_shaman_rockbiter_badge` | SHAMAN Trackers | shaman.lua:1573 `~= true` | nil = OFF | OK |
| 19 | `show_druid_pips` | DRUID Trackers | druid.lua:1234 `== true` | nil = OFF | OK |
| 20 | `show_druid_shred_countdown` | DRUID Trackers | druid.lua:1233 `== true` | nil = OFF | OK |
| 21 | `show_druid_maul_badge` | DRUID Trackers | druid.lua:122/1236 `~= true` / `== true` | nil = OFF | OK |
| 22 | `show_druid_omen_glow` | DRUID Trackers | druid.lua:637 `~= true` | nil = OFF | OK |
| 23 | `show_druid_gcd_tick` | DRUID Trackers | druid.lua:1235 `== true` | nil = OFF | OK |
| 24 | `hud_show_tf` | DRUID HUD Icons row descriptor | druid.lua:1700 (`key="tf"` slot) → hud.lua:463 `show_key="hud_show_"..key` → hud.lua:611 `== false` hides | `true` (hide-on-false shape) | OK — full chain present |
| 25 | `hud_show_berserk` | DRUID HUD Icons row descriptor | druid.lua:1701 → hud.lua:463 → hud.lua:611 | `true` (hide-on-false shape) | OK — full chain present |
| 26 | `show_shaman_spell_positions` | SHAMAN Trackers | shaman.lua:1703 `== true` | nil = OFF | OK |
| 27 | `show_shaman_dw_sync` | SHAMAN Trackers | shaman.lua:1832 `~= true` | nil = OFF | OK |

Group placement / descriptions: unchanged from the options pass (new headers PALADIN "Judgement & Cooldowns", HUNTER "Pet Badges" intact); no default flipped on; no key renamed. One in-scope factual fix: the stale druid-HUD code comment ("no druid icon glows…") now reads "Tiger's Fury and Berserk glow in combat once ready", matching the shipped descs (comment-only, zero behaviour change).

§6 gaps re-confirmed still correctly unwired: `druid_pips_x`/`druid_pips_y` (no hits repo-wide outside docs — consumer is the out-of-scope pips factory/call site); `practice_aw_includes_pot`/`practice_aw_includes_sob` (engine/UI-only, explicitly deferred at practice.lua:735-737, zero widget refs in scope); `/st diag reset` verb (no `reset` verb exists in main.lua/diag.lua — nothing to wire). No in-scope consumer for any gap item → all correctly left unwired.

## 4. Tests

- `lua5.1 tests/options_load_state.lua` → **537 checks, 0 failed** (was 521; new §7 adds 16 checks pinning all six Task-A removals plus hand-group displayed names).
- `bash tests/run.sh` → 35 steps, 3 failed: `bars_state` + `hud_state` (the expected final-reconcile count pins, untouched per the brief) plus `toc_check` `## Interface` row — a parallel lane edited `SwedgeTimer.toc` (10:56:29Z, after this pass's edits) changing the advertised list to `11509, 20506, 38002, 16001, 120105` while the suite expects `120100`. Out of this pass's scope; not touched.
- `luacheck .` → 0 errors (28 warnings repo-wide; scope files contribute only the 3 KEEP-ruled whitespace lines).
- Order-collision posture unchanged (no widget added or moved by this pass).

## 5. Mutation proofs (`/tmp/opencode/mut_repo/` full-tree copy; each applied, checked, restored, `cmp` byte-identical)

| ID | Reintroduction | Result |
|---|---|---|
| M1 | `local LSM` re-added to config.lua | 537 checks, **1 FAIL** (wiring: config.lua fetches no LSM handle) |
| M2 | `local title = settings.title` re-added | 537 checks, **1 FAIL** (no dead title local) |
| M3 | `color_getter = function(self, …)` restored | 537 checks, **1 FAIL** (no shadowing self param) |
| M4 | `local print = st.utils.print_msg` re-added | 537 checks, **1 FAIL** (no print alias) |
| M5 | `local addon_name, st` restored in option_table_presets.lua | 537 checks, **1 FAIL** (st vararg unbound) |
| M6 | `english_class` shadow restored in get_player_class_pretty | 537 checks, **1 FAIL** (exactly one english_class binding) |

Restored tree `cmp`-clean on all five files; final copy run 537/0.

## 6. UNCONFIRMED (in-client list)

- Rendered options pages (widget placement/orders, the two headers) never opened in a client — the suite pins the tree, not the pixels.
- `hud_show_tf` / `hud_show_berserk` shipping true remains presentation-only (nil behaves identically); confirm the HUD icons row with the HUD master on.
- The recommended-true defaults (hunter / shaman round-1 + round-2 / druid) remain OFF pending owner in-client verification.
- The `SwedgeTimer.toc` `## Interface` mismatch belongs to the lane that edited the TOC; confirm with that lane before release.
