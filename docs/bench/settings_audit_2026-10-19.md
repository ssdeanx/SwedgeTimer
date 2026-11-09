# Settings UX audit per class — 2026-10-19 (report-only)

Scope: every shipped feature has every option it needs; every widget name/desc
user-understandable; panel order/alignment correct per class. Read
`option_tables.lua`, `config_presets.lua`, `classes/*.lua` (+ `hunter_ui.lua`,
`practice_ui.lua` where the class reads through them), `tests/options_load_state.lua`.
No edits made (designer lane owns `option_tables.lua` + `config_presets.lua`).
Target file verified absent via in-lane glob before writing.

Method: widget inventory per `ST.class_opts_funcs.<CLASS>` + shared
`hud_rotation_widgets` builder (orders 8.x/9.x) + `hud_template_widget` (8.02);
consumer inventory = `db.<key>` / `db_class.<key>` / `get_class_table().<key>` /
string-literal option keys in the class module (+ `hunter_ui.lua` for hunter,
`practice_ui.lua` for practice keys); defaults inventory = `ST.<TOKEN>.defaults`
+ shared `ST.class_defaults` + documented nil-off design (`== true` reads, no
default ships — pinned by tests §6). Structural validity (types, get/set, unique
orders ≥ 8.0, casing) is pinned by `tests/options_load_state.lua` and NOT
re-audited here except where it surfaces as UX (the 3.1/3.10 numeric collision).

Standing rules respected: no new widgets invented (missing rows give spec shape +
consumer `file:line` only); nil-off stays nil-off; no default-visible change
proposed without an explicit gate note.

## Cross-class findings (apply to every panel, fixed once)

| # | Finding | Evidence |
|---|---|---|
| X1 | Bare `name = "Enable"` repeated 10+× per panel (paladin 1.11/2.2/5.1, warrior 2.2, hunter 1.1/2.1/3.1/4.1/5.1/6.1/7.1, druid 4.3/11.1, shaman 1.1, rogue 4.1). In AceConfig search results the toggle reads "Enable" with no context. | `option_tables.lua:1371,1493,1907,2889,3174,3333,3360,3389,3444,3463,3501,3552,3838,4149,4339,4572,5008` |
| X2 | Bare `name = "Color"` repeated (warrior `hs_color` :2816 + `cleave_color` :2837, hunter `raptor_strike_color` :3341 / `steady_shot_color` :3368 / `hunter_cast_bar_color` :3408, druid `maul_color` :3928, paladin `aow_glow_color` :2516 etc.). Same search-context problem as X1. | cited lines |
| X3 | Three identical `name = "Lock frame"` toggles inside one class panel (HUD 8.11, guide 5.11/4.11/7.11/14.11/3.11, rotation label 9.11). Indistinguishable in search; drag-target unclear. | `:839,1103,1915,2290,2619,3182,3570,4157,4580,5016` |
| X4 | Rotation `Format` select values hardcode the paladin example in ALL six panels: `{ key = "2/3", labelled = "Rotation: 2/3", steps = "CS, Twist, Twist", both = "2/3 - CS, Twist, Twist" }`. Warrior/hunter/shaman/druid/rogue users are offered "CS, Twist, Twist" as the steps example for their own class. The `format_desc` param is per-class but `values` is shared. | builder `:1125`; paladin local `:2642` (same literal) |
| X5 | NAG visibility `name = "Show guide"` vs HUD `name = "Show HUD"` vs rotation `name = "Show text"` — three names for the same "when is this frame visible" concept. Rotation should read "Show label" to match its frame ("Rotation Text" header + "Lock frame"). | builder `:1108-1112` (`Show text`), paladin `:2624-2628`, all NAG `:1920-1928` etc. |

Suggested rewrites for X1–X3/X5 (designer wording, no behavior change):
X1 → `"Enable <thing>"` (e.g. hunter 1.1 `"Enable Raptor Strike color"`,
paladin 5.1 stays `"Enable"` ONLY as the panel master — it is the single
top toggle of its section; all non-master Enables get the qualifier).
X2 → `"<thing> color"` (e.g. `"Heroic Strike color"`, `"Raptor Strike color"`).
X3 → `"Lock HUD frame"` / `"Lock guide frame"` / `"Lock label frame"`.
X5 → rotation `name = "Show label"`, desc unchanged.
X4 → per-class `values` (designer supplies each class's step example; engine
already localizes the label via `get_rotation_key` — options only need display
text). No default change: selected key (`key`/`labelled`/`steps`/`both`) is
class-agnostic.

## Paladin

### Missing options

| # | Shipped behavior (consumer) | Spec shape + consumer | Note |
|---|---|---|---|
| P-M1 | NONE — full coverage. Every `db.<key>` the module reads has a widget + default (or documented nil-off / session state). Twist mana governor wired (`twist_mana_threshold_pct` range 0–100, nil-safe; consumer `classes/paladin.lua:2815`). Lust narrow, reseal marker, hit-rate badge + persist, JotC bar, CD row, judgement marker, seal icons all wired. | — | No action. |
| P-M2 | Shockadin HS/AM guide slots have NO HUD counterparts by design. Guide slots `holy_shock` (20930) + `aura_mastery` (407624) render in `nextaction_ui` only when the engine prompts (`classes/paladin.lua:3111-3119,3173-3179`); `ST.PALADIN.HUD_SLOTS` (`:3277-3284`) carries cs/judgement/consecration/exorcism/trinkets/wings only, and no `hud_show_holy_shock` / `hud_show_aura_mastery` widgets exist. | IF the designer wants them on the HUD: two `toggle` + `true` defaults (hide-on-false shape, `option_tables.lua` § Paladin icons ~8.48/8.49) reading `classes/paladin.lua` HUD provider. | Designer decision, not a defect. HS has a 30 s CD (6 s w/ rune) so a HUD icon is plausible; AM likewise. Filed here, not built. |

Session-state keys correctly WITHOUT widgets (not missing):
`twist_score_attempts` / `twist_score_successes` (profile mirror of the badge
counts), `twist_window_time_before_swing`, `twist_lust_at`, `jotc_expires` etc.

### Unclear copy

| # | Widget (order) | Current text | Suggested rewrite |
|---|---|---|---|
| P-C1 | `twist_feedback_enabled` (3.4) name/desc | `"Twist attempt feedback"` / `"Shows attempt feedback on the timer bar, and the success text when that is enabled."` | `"Twist attempt flash"` / `"Flash the bar while two seals are active on the swing; the floating text has its own toggle below (Success text)."` — current desc buries the two-part behavior. |
| P-C2 | `twist_color_twisting` (3.5) | `"Armed / attempted color"` | `"Twist armed color"` — matches runtime states (`twist_armed`, `twist_attempt_pending` in `classes/paladin.lua`), drops the slash. |
| P-C3 | `twist_color_cant` (3.6) | `"'Can't twist' warning color"` | `"Twist impossible color"` — matches engine flag `twist_impossible`; avoids quotes-in-name rendering. |
| P-C4 | `lag_detection_enabled` (4.1) | `"Warn on impossible twists"` | `"Impossible-twist warning"` — parallel with P-C3; desc already explains. |
| P-C5 | `twist_padding_mode` (4.4) values | `None/Fixed/Dynamic` with desc covering both | Append the effective behavior to the names is not possible in select values; instead extend desc tail: `"Fixed uses the offset below; Dynamic uses the multiplier + offset above."` — currently the reader must infer which option the two controls below belong to. |
| P-C6 | `nextaction_show_label` (5.24) | `"Show \"Next action:\" label"` (escaped quotes in source) | `"Show frame title"` — the literal quoted string renders awkwardly and duplicates the next two rows' pattern. |
| P-C7 | `practice_desc` (7.05) tail | `"…are still in development."` | Name the shipped subset: `"…Only weapon speed, result styling and panel position ship as options; rotation lock, haste buttons and keybinds are still in development."` — matches `practice_ui.lua:60` filed list. |

### Order / alignment

| # | Current | Proposed | Rationale |
|---|---|---|---|
| P-O1 | `twist_feedback_enabled` (3.4, NO `disabled` gate) vs sibling `twist_marker_enabled` (3.2, gated on `twist_enabled`) vs `twist_success_glow_enabled` (3.96, ungated). Three master-adjacent toggles, two gating conventions. | Gate 3.4 and 3.96 on `twist_enabled` like 3.2 (or document why feedback/glow intentionally work with the master off). | A user who turns "Enable twist helpers" (3.1) off still gets attempt flashes — surprising. Nil-safe either way; gate = no visible change for default-on profiles. |
| P-O2 | `judgement_marker_enabled` (3.985) + `seal_icons_enabled` (3.99) sit INSIDE the twist block (3.x) before `lag_header` (4.0), but both are tracker visuals, not twist visuals. | New `tracker_header` at 3.95 (or move both to 4.x ahead of lag, renumbering lag 4.0→4.5). | Current placement reads as "twist sub-options"; they are seal/judgement feedback. |
| P-O3 | `twist_mana_threshold_pct` (3.45) renders between `twist_lust_override_enabled` (3.43) and `twist_color_twisting` (3.5). | Move to 3.46+ after `reseal_marker_enabled` (3.44) group, or its own `mana_header` at 3.46. | Mana governor is a reseal behavior, not a color; sandwiched between a lust toggle and color rows it is easy to miss. |

Panel flow otherwise correct: seals 1.x → AoW 2.x → trackers 2.7x → twist 3.x →
lag 4.x → NAG 5.x → sounds 6.x → practice 7.x → HUD 8.x (template 8.02 between
desc 8.01 and master 8.1 — correct) → rotation 9.x → sim 10.x.

## Warrior

### Missing options

| # | Shipped behavior (consumer) | Spec shape + consumer | Note |
|---|---|---|---|
| W-M1 | Hamstring weave filler: guide slot `hamstring` (7373) exists and the engine weaves it (`classes/warrior.lua:2245-2246,2346,2417-2420,2567`), but there is NO hamstring toggle/threshold widget and NO `hud_show_hamstring` HUD slot. User cannot force/never hamstring or tune it. | IF wanted: one `toggle` (opt-in, nil-off) + optional `range` threshold; consumers `classes/warrior.lua:2346` (slot) + `:2567` (inputs). | Lane `warrior-hamstring-slot` deliberately rode the existing engine ("slot shows GCD swipe + HUD state"); filed here as the options half. Designer decides: engine-only is defensible, but then the panel should say so (see W-C4). |
| W-M2 | Victory Rush: engine has NO rule (operator: SKIP, HOLD DORMANT). No widget ships. | Correctly unwired — do NOT add. | Recorded so a future lane does not "close the gap" against the operator order. |
| W-M3 | W2 Battle Shout: badge + suppression toggles shipped (`show_warrior_battle_shout_badge` 3.17, `show_warrior_commanding_suppression` 3.19). Complete. | — | No action. |

All tracker bars (Deep Wounds/Sunder/Rend/TC/Demo/Shield Block/Slam/OP/Rampage/
BANK/Desync) have toggle + color where applicable; `guide_execute_pct` range
ships sim-exact 20 (tests §10b pins).

### Unclear copy

| # | Widget (order) | Current text | Suggested rewrite |
|---|---|---|---|
| W-C1 | `hs_color` (1.2) / `cleave_color` (1.4) name | both `"Color"` | `"Heroic Strike color"` / `"Cleave color"` (X2). |
| W-C2 | `insufficient_rage_color` (1.6) | `"Insufficient Rage color"` / `"Color to use when the player drops below the rage threshold for the queued ability."` | `"Queued-but-unaffordable color"` / `"Color while a queued Heroic Strike / Cleave sits above your current rage."` — current desc never names the abilities. |
| W-C3 | `show_warrior_bank_cue` (3.16) | `"BANK cue"` / `"Show an amber edge and a centred BANK label while a queued on-next-attack ability is unaffordable in combat."` | `"Queued-ability BANK cue"` — keeps the on-bar BANK label text, but the option name now explains itself in search. |
| W-C4 | `show_warrior_desync_alert` (3.18) | `"Desync alert"` / `"Show a small spark on the mainhand bar where the offhand will land while your swings are desynced (off by default)."` | `"Offhand desync spark"` / `"Show a spark where the offhand will land while mainhand and offhand swings are desynced (off by default)."` — names both hands. |
| W-C5 | `hide_in_tank_spec` (0.81) / `hide_in_arms_spec` (0.82) desc | `"…(activated when Improved Defensive Stance is talented)."` / `"…(activated when Bladestorm is talented)."` | Append detection caveat: `"…Talent detection is a heuristic; verify in-client."` — talent-name detection is UNCONFIRMED-grade (cf. `bench/verify_bank.md` D1 precedent). |
| W-C6 | `warrior_demo_shout_bar_color` (3.10) vs `show_warrior_demo_shout_bar` (3.9) | toggle `"Demo Shout bar"`, color `"Demo Shout color"` | Fine as-is; listed only to anchor W-O1 (the color's ORDER, not its copy, is the defect). |

### Order / alignment

| # | Current | Proposed | Rationale |
|---|---|---|---|
| W-O1 (REAL) | `show_warrior_deep_wounds_bar` order **3.1** vs `warrior_demo_shout_bar_color` order **3.10**: `3.10 == 3.1` numerically, so AceConfig orders the two rows ambiguously (Lua number equality; `tests/options_load_state.lua` §4c explicitly scopes its uniqueness check to ≥ 8.0 to dodge this pre-existing collision). | Renumber the tracker color rows to three decimals: `warrior_demo_shout_bar_color` 3.10 → **3.101**, `warrior_shield_block_bar_color` 3.12 stays, or renumber the whole 3.1–3.19 band to 3.10–3.28 in file order. Any scheme where every order literal is numerically unique. | Two widgets share one sort key; in-client row order is undefined. No default change (order-only edit, designer lane). |
| W-O2 | `guide_execute_pct` (4.16) is the last NAG row but reads as a child of position fields (X 4.14/Y 4.15). | Move to 4.13 (right after `nextaction_icon_size`, before X/Y) or its own `guide_thresholds_header` at 4.16 with the range at 4.17. | Thresholds should group with behavior, not geometry. Minor. |

Panel flow correct otherwise: spec gates 0.8x → queue colors 1.x → Bloodsurge
2.x → trackers 3.x → NAG 4.x → HUD 8.x → rotation 9.x → sim 10.x.

## Hunter

### Missing options

| # | Shipped behavior (consumer) | Spec shape + consumer | Note |
|---|---|---|---|
| H-M1 | `hunter_multi_target` toggle (7.2) has NO consumer: `hunter_guide.lua`, `classes/hunter.lua` gather and `hunter_ui.lua` never read `multi_target` (pinned by tests §11b FOLLOWUP). The widget promises "the guide prefers Multi-Shot" and the engine does not. | Wire (engine lane, OUT of options scope): `toggle` already ships; consumer needed in `hunter_guide` inputs + `classes/hunter.lua` gather. | Do NOT remove the widget (tests §6 + §11 pin it as the filed wire); do NOT add a second widget. Options half is done. |
| H-M2 | Guide-only slots with no HUD counterpart: `chimera`, `explosive`, `arcane`, `kill_shot`, `sniper`, `hawk` appear in `classes/hunter.lua` guide-slot tables (`guide_slots_base`/`_wrath`/`_tbc`/`_era_sod`/`_forever`) but `ST.HUNTER.HUD_SLOTS` (9 slots: steady/raptor/kill_command/multi/bestial_wrath/rapid_fire/aimed/trinkets) has no entries and no `hud_show_*` widgets exist for them. | IF wanted: one `toggle` per slot that ships (hide-on-false shape, like siblings) + descriptor in `classes/hunter.lua`; options shape = existing `hud_show_*` row (`toggle`, order 8.4x). | Likely intentional (per-client conditional shots; HUD is the steady-rotation core). Filed as the decision, not built. |
| H-M3 | Practice: only the Shot Report `execute` (7.32) ships; no hunter practice-geometry/result options (paladin-only 7.2–7.36). Hunter drills run via the shared registry (`bench` practice-parity: 8 drills, all classes). | No widget owed unless the designer wants per-class practice geometry — `/st practice` starts sessions globally. | Note only; paladin 7.x is Twist Practice-specific, not a template other classes must copy. |

Nil-off by design (NOT missing — no default ships, `== true` reads):
`hunter_cast_zone_enabled`, `hunter_target_warning_enabled`,
`hunter_bw_badge_enabled`, `hunter_frenzy_stacks_enabled`,
`hunter_readiness_badge_enabled`, `hunter_iss_badge_enabled`,
`hunter_oom_viper_badge_enabled`, `hunter_lnl_badge_enabled` (consumers
`hunter_ui.lua:717,790,931,1096-1097,1155,1232` + `classes/hunter.lua:829`).
`hunter_multi_target` likewise nil-off. `hunter_shot_report` is `execute`
(no db key — correct).

### Unclear copy

| # | Widget (order) | Current text | Suggested rewrite |
|---|---|---|---|
| H-C1 | `hunter_multi_target` (7.2) | `"Multi-target mode (manual) (future)"` / `"Treat the fight as 2+ targets: … Manual because automatic target counting is unreliable in raids."` | `"Multi-target mode (manual, not wired yet)"` — `"(future)"` reads as vapor; the honest state is widget-ships/engine-owed (tests §11b). Keep desc, change name so users do not expect it to work today. |
| H-C2 | `hunter_cast_bar_color` (3.3) desc | `"…The Auto Shot window always uses this colour; live casts overlay it in green when the cast is clip-safe and red when it is not."` | `"…The Auto Shot window always uses this colour; live casts tint green while stopping is safe and red while it is not."` — "clip-safe" is implementation jargon; `hunter_ui.lua:666` tint key is the safe/stop verdict. |
| H-C3 | `hunter_iss_badge_enabled` (7.43) | `"ISS tint"` / `"Glow the Steady Shot and Aimed Shot HUD icons while the Improved Steady Shot proc is banked (off by default)."` | `"Steady Shot proc tint (ISS)"` — name expands the acronym once; desc already does. |
| H-C4 | `hunter_oom_viper_badge_enabled` (7.44) | `"OOM Viper badge"` | `"Low-mana Viper badge (OOM)"` — "OOM" first is chat slang; the desc's "while mana sits below the swap band" is the plain version. |
| H-C5 | `hunter_lnl_badge_enabled` (7.45) | `"Lock and Load badge"` / `"Show an \"LnL\" badge while the Lock and Load trap-proc window is live…"` | `"Trap-proc badge (Lock and Load)"` — names the trigger (trap proc), keeps the talent name. |
| H-C6 | `hunter_readiness_badge_enabled` (7.42) | `"Readiness 2x window"` | `"Readiness double-Rapid Fire window"` — "2x" alone is cryptic; `classes/hunter.lua:700` comment calls it the "double-RF window". |
| H-C7 | Six `"Enable"` + three `"Color"` (X1/X2) | see X1/X2 | e.g. 3.1 `"Enable cast bar"`, 4.1 `"Enable range helper"`, 5.1 `"Enable Rapid Fire bar"`, 6.1 `"Enable aspect icon"`. |

### Order / alignment

| # | Current | Proposed | Rationale |
|---|---|---|---|
| H-O1 | `hunter_multi_target` (7.2) sorts AFTER guide geometry (X 7.14/Y 7.15) because `7.2 > 7.15` numerically: Enable 7.1 → Lock 7.11 → Show 7.12 → Size 7.13 → X 7.14 → Y 7.15 → **multi 7.2** → Shot Report header 7.3 → … | Move multi-target to **7.101** (directly under `nextaction_enabled` 7.1) OR to its own `multitarget_header` at 7.16 (after Y, before Shot Report) with desc noting the unwired state. | A guide-*behavior* toggle must not sit between position fields and an unrelated analytics section. 7.101 keeps Enable→behavior→frame→geometry flow. |
| H-O2 | Shot Report block (header 7.3 / desc 7.31 / button 7.32) splits NAG behavior (7.1–7.2) from the badge layer (proc header 7.4). | Move Shot Report AFTER proc badges: header 7.3→**7.5**, desc →7.51, button →7.52 (proc block stays 7.4x). | Shot analytics is post-fight; badges are in-fight. Current interleave reads as "report is a guide control". |
| H-O3 | `hunter_cast_zone_enabled` (3.4) sits directly under `hunter_cast_bar_color` (3.3) but renders ON THE RANGED BAR, not in the cast bar — correct section (cast bar family), but its `disabled` gate is absent (sibling height/color gate on `hunter_cast_bar_enabled`; zone does not). | Add `disabled` on `not db.hunter_cast_bar_enabled` OR document independence in desc (`"works without the cast bar"`). | If the zone needs the bar, it should grey out; if independent, say so — currently ambiguous. Consumer `hunter_ui.lua:717` reads it independently of `:591`, suggesting independent → desc fix suffices. |

Panel flow otherwise correct: queue colors 1–2 → cast bar 3.x → target warn
3.5x → range 4.x → Rapid Fire 5.x → aspect 6.x → pet 6.5x → NAG 7.0–7.2 →
(report 7.3) → badges 7.4x → HUD 8.x → rotation 9.x → sim 10.x.

## Shaman

### Missing options

| # | Shipped behavior (consumer) | Spec shape + consumer | Note |
|---|---|---|---|
| S-M1 | NONE for shipped visuals. Weave families (LB/CL/HW/LHW/CH via `weave_family_*` 1.2–1.24 reading nested `weave_families`, consumers `weave.lua` via `classes/shaman.lua`), MW toggle, marker/spark sizes, all tracker bars/badges, lust badge, DW/Flurry readout, FS refresh — all wired. | — | No action. |
| S-M2 | Correctly UNWIRED (filed, do not build): dedicated hold/SR/ES thresholds — live hold stays the tint reuse (`show_shaman_wf_hold_tint`, `classes/shaman.lua:2600`); `weave.should_pause_twist_for_mana` (`weave.lua:632-637`) and SR/ES engine constants (`shaman_guide.lua:244-252`) have no db keys and no widgets (pinned tests §13c). FE display, totem handling likewise filed. | — | Recorded so a future lane does not invent `stormstrike_hold` / `mana_pause` / `sr_threshold` / `es_floor` widgets; tests §13c fails if they appear without the engine wire. |

`weave_families` nested defaults (`config_presets.lua:927-933`) are NOT missing
top-level defaults — the key-specific getter/setter pair
(`option_tables.lua:4307-4320`) reads the nested table by design.

### Unclear copy

| # | Widget (order) | Current text | Suggested rewrite |
|---|---|---|---|
| S-C1 | `show_shaman_dw_sync` (2.91) | `"DW sync / Flurry readout"` / `"Show the dual-wield sync readout and the live Flurry proc countdown beside the bar."` | `"Dual-wield sync / Flurry readout"` — expand DW in the name (desc already does). |
| S-C2 | `show_shaman_lust_status` (2.92) desc tail | `"…Trinket internal cooldowns stay on the HUD trinket row; every listed cooldown length is unconfirmed until an in-client combat-log read confirms it."` | Split: keep `"Show the Bloodlust / Heroism remaining time beside the bar (\"BL ?\" while the read is inconclusive; hidden while no lust is up)."` and MOVE the trinket/cooldown sentence to the HUD trinket-row desc (or delete — it describes a different widget). Current tail answers a question the badge did not ask. |
| S-C3 | `show_shaman_cooldown_badges` (2.4) | `"Stormstrike / Shamanistic Rage badges"` | `"Stormstrike + Shamanistic Rage badges"` — slash reads as either/or; both show. |
| S-C4 | `show_shaman_spell_positions` (2.9) | `"Spell position row"` / `"Show the cast-start zone, the per-spell icons at their latest safe starts and the effective cast times above the bar."` | `"Safe-cast position row"` — distinguishes from the spark/marker above; desc is good. |
| S-C5 | `weave_mw_enabled` (1.3) desc | `"Reduce the effective cast time by 20% per Maelstrom Weapon stack; 5 stacks are instant."` | `"Count Maelstrom Weapon stacks toward the cast time (20% per stack; 5 stacks are instant)."` — current reads as a fact about the game, not what the toggle does. |

### Order / alignment

| # | Current | Proposed | Rationale |
|---|---|---|---|
| S-O1 | Trackers 2.1–2.5 are the ported reference set, then 2.6 Stormstrike bar, 2.7 WF hold, 2.8 Rockbiter, 2.9 spell positions, 2.91 DW sync, 2.92 lust — chronological accretion, no grouping headers. | Add two headers: `timers_header` at **2.55** (Stormstrike bar 2.6 + Flame Shock is 2.3… hmm) — simpler: move 2.6 next to 2.3 (both are *target debuff* bars: FS 2.3, SS-vuln 2.6) and group 2.7–2.92 under a `badges_header` at **2.65**. | Target timers vs bar-adjacent badges are currently interleaved by landing order; grouping matches the warrior tracker section (bars then badges). Minimal renumber, no behavior change. |
| S-O2 | `guide_flameshock_refresh` (3.16) is the ONLY guide threshold (kept 3, sim-exact 0 filed; tests §10a pins). Position after X/Y (3.14/3.15) mirrors the hunter multi-target problem at smaller scale. | Move to **3.101** (under `nextaction_enabled` 3.1). | Behavior-before-geometry, consistent with proposed H-O1. |

Panel flow otherwise correct: weave 1.x → trackers 2.x → NAG 3.x → HUD 8.x →
rotation 9.x → sim 10.x. `hud_template` 8.02 placement correct.

## Druid

### Missing options

| # | Shipped behavior (consumer) | Spec shape + consumer | Note |
|---|---|---|---|
| D-M1 | NONE for shipped visuals. Energy tick/pips/shred/maul-badge/omen/gcd-tick/TTD toggles + trackers + `guide_rip_refresh` / `guide_rake_refresh` / `guide_rip_min_cp` (2–5, default 4; consumer `classes/druid.lua:1707`, engine `druid_guide.lua:515-520`) all wired. | — | No action. |
| D-M2 | Pips position: `bars.lua` factory consumes `opts.x`/`opts.y` but the only call site passes literals and no `druid_pips_x`/`druid_pips_y` keys exist (pinned tests §8c as correctly unwired). | Do NOT add. | Recorded; the pips row is positioned by the bar, not user-placeable. |

Faerie Fire plumbing / Forever Berserk hold / fight-elapsed gates are filed
follow-ups in the druid lane journal — no widget owed until the engine reads them.

### Unclear copy

| # | Widget (order) | Current text | Suggested rewrite |
|---|---|---|---|
| D-C1 (REAL BUG) | `maul_color` (11.2) desc | `"Color to use when Heroic Strike is queued."` (`option_tables.lua:3931`) | `"Color to use when Maul is queued."` — copy-paste from warrior `hs_color` (`:2819`, identical string). The NAME (`"Color"`, X2 → `"Maul color"`) and consumer (`db.enable_maul_color`, `classes/druid.lua`) are all Maul; only the desc says Heroic Strike. |
| D-C2 | `enable_maul_color` (11.1) | `"Enable Maul Color"` (capital C, only such casing in the file) | `"Enable Maul color"` — matches every sibling (`"Enable Heroic Strike"`, `"Enable Raptor Strike color"` style). |
| D-C3 | `show_druid_pips` (13.11) | `"Combo points"` / `"Show combo points as pips under the bar in cat form (the row glows at 5)."` | `"Combo-point pips"` — the panel already has an energy bar + tick marker; "Combo points" alone does not say pips. |
| D-C4 | `show_druid_maul_badge` (13.13) | `"Maul cap badge"` / `"Show the at-cap time (\"Cap Ns\") below the bar while rage is capped."` | `"Rage-cap Maul badge"` — "Maul cap" reads as "Maul cap (talent?)"; the badge is about being AT rage cap. |
| D-C5 | `show_druid_ttd_readout` (13.16) | `"Time-to-die readout"` | `"Target time-to-die readout"` — every sibling names its target ("your own Mangle/Rip/Rake"); TTD's target is implied only in desc. |

### Order / alignment

| # | Current | Proposed | Rationale |
|---|---|---|---|
| D-O1 (REAL) | Local sections run 3.x (form vis) → 4.x/5.x (form colors) → **11.x (Maul) → 12.x (rage) → 13.x (trackers) → 14.x (NAG)**, while the shared builder injects HUD **8.x** + rotation **9.x** + sim **10.x**. Numerically HUD/rotation/sim render BETWEEN form colors (5.5) and Maul (11.0). Every other class ends class-visuals → trackers → NAG → HUD → rotation → sim; druid alone shows HUD/rotation/sim mid-panel. | Renumber druid locals before the builder runs: form vis 3.x stays, form colors 4–5.x stay, Maul 11.x→**6.x**, rage 12.x→**6.5x**, trackers 13.x→**7.x**, NAG 14.x→**7.5x**… OR (fewer edits) bump builder orders for druid only — NOT recommended (builder is shared). Preferred: renumber 11/12/13/14 → 6/6.5/7/7.5, leaving 8/9/10 for HUD/rotation/sim. | Panel currently reads: forms → [HUD] → [rotation] → [sim] → Maul → trackers → guide. A feral user meets the HUD before the class's own Maul color. Order-only change; no defaults touched. |
| D-O2 | `lb02` (4.4) is an empty `description name = ""` spacer between `use_form_colors` (4.3) and `form_color_bear` (5.0), mirroring warrior's empty `lb0/lb1/lb2` headers (1.03/1.45/1.55, `name = ""`). | Delete the spacers OR give them names; empty headers/descriptions render as blank rows. | Cosmetic; five blank rows across two panels (warrior ×3, druid ×1). Designer call. |

## Rogue

### Missing options

| # | Shipped behavior (consumer) | Spec shape + consumer | Note |
|---|---|---|---|
| R-M1 | R-T3 template writes `hud_show_kidney` / `hud_show_restealth` / `hud_show_bandage` db keys with NO widgets (`option_tables.lua:5115-5119` comment admits provisional; consumer `classes/rogue.lua:1167` gates `kidney`/`restealth`/`bandage` on exactly-true, nil-safe; titles at `:984-986`). Picking "R-T3 PvP Utility" writes keys the user can never toggle individually; manual tweaks read back Custom without showing which keys differ. | Three `toggle` widgets (hide-on-false shape, orders ~8.48–8.50 after `hud_show_coldblood`) + `false`→`true` defaults? NO — defaults must stay absent-or-false (nil = off, hide-on-false shape like siblings; tests §4 pins sibling slots ship `true`, but these three are UNCONFIRMED-scope: ship WITHOUT a `true` default, nil = hidden, template turns them on). Consumers `classes/rogue.lua:984-986,1167-1223`. | Owned by in-flight `rogue-followups` lane per the template comment; filed here with shape so the wire is options-complete when the engine half lands. Suite exemption lives in tests (template id list), not in the panel — the panel half is simply absent. |
| R-M2 | Cold Blood: HUD slot + `hud_show_coldblood` toggle ship, but there is no guide threshold/rule option (guide has no Cold Blood timing input; `classes/rogue.lua:34` notes the gate + filed widget/default). | No widget owed — HUD icon correctly has none beyond the slot toggle. | Note only; do not invent a Cold Blood guide threshold. |
| R-M3 | Practice: rogue drills run via the shared registry; no rogue practice options ship (see H-M3). Paladin-only 7.x is Twist-specific. | No widget owed. | Note only. |

All energy/pool/threshold/SS/swap/poison/duty/NAG keys round-trip (tests §9
pins the full three-way contract + engine-default fallback + color gates).

### Unclear copy

| # | Widget (order) | Current text | Suggested rewrite |
|---|---|---|---|
| R-C1 | `rogue_pool_band_pre` (1.3) / `rogue_pool_band_post` (1.31) | `"Pre-tick band"` / `"Energy threshold at or above which the next tick would cap the bar."` and `"Post-tick band"` / `"Energy threshold to respect immediately after a tick."` | `"Pool: don't spend below (pre-tick)"` / `"Pool: don't spend below (post-tick)"` — names the ACTION (pooling = holding spend); current names describe the timing, not the decision. Keep descs. |
| R-C2 | `rogue_tea_energy_max` (2.76) | `"Thistle Tea energy"` / `"Suggest Thistle Tea while energy is at or below this."` | `"Thistle Tea drink-at energy"` — current name reads as the tea's energy cost. |
| R-C3 | `rogue_rupture_min_ttd` (2.72) desc | `"Dump Eviscerate instead of starting a Rupture when the target is estimated to die inside this many seconds (the addon's own health-velocity estimate; an unknown time-to-die never suggests a finisher on a guess)."` | Keep, but name → `"Rupture skip-if-dying-within (s)"` — the desc is the panel's best unknown-hides explanation; the name should carry the skip semantics. |
| R-C4 | `postswing_desc` (3.02) | Long single desc covering Era-only SS, Era/TBC/Forever swap, poison, unknown-hides. | Split into three description rows (one per cue) OR keep — current is accurate but 5 clauses. Designer call; content is correct. |
| R-C5 | `rogue_ea_duty` (2.6) | `"Expose Armor duty"` (name) is good; desc `"Treat keeping Expose Armor on the target as your job … Leave off when someone else handles the armor debuff."` | Append: `"Off by default; the guide never suggests Expose Armor while off."` — states the off-behavior the engine implements (`rogue_guide` duty-gated). |

### Order / alignment

| # | Current | Proposed | Rationale |
|---|---|---|---|
| R-O1 | `rogue_ea_duty` (2.6) sits alone between `duty_desc` (2.02) and `thresholds_header` (2.7): gap 2.02→2.6→2.7 with 2.1–2.5 empty. | Move duty toggle to **2.03** (directly under its desc) and thresholds header stays 2.7. | The duty decision reads as part of the thresholds block today; it is the section's only control and should hug its desc. |
| R-O2 | Thresholds 2.71–2.76 follow the header directly — correct. Post-swing 3.x → NAG 4.x → HUD 8.x → rotation 9.x → sim 10.x — correct flow. | No change. | Cleanest panel of the six after R-O1. |

## Already-pinned follow-ups (do NOT re-file as new gaps)

These are asserted by `tests/options_load_state.lua` so a silent drift fails
the harness; listed here so the designer does not treat them as fresh findings:

- Hunter `hunter_multi_target` orphan (H-M1): tests §11b pins widget-present +
  consumer-absent; the wire (not another widget) closes it.
- Shaman dedicated hold/SR/ES unwired (S-M2): tests §13c pins absence.
- Hard-wait `hard_wait` / `strict_sequence` unwired: tests §13b pins absence
  (render filed at `nextaction_ui`, feed at `classes/paladin.lua:2897`).
- Druid pips x/y unwired (D-M2): tests §8c pins absence.
- Rogue R-T3 provisional keys (R-M1): template exemption documented in
  `option_tables.lua:5115-5119`; suite pins the id list (tests §12), panel half owed.
- Kept-with-reason numeric defaults (tests §10): shaman FS refresh 3 (sim 0),
  druid rip/rake 4 (legacy fallback), paladin filler 35/30 + CS 900, rogue
  bands/thresholds (unknown-family fallback; per-client sims live engine-side).
- Warrior 3.1/3.10 collision is the ONE structural pin the suite dodges
  (§4c scopes uniqueness to ≥ 8.0): W-O1 proposes the renumber; the suite's
  scope comment (`option_tables.lua` warrior section + tests §4c) should be
  updated in the same commit that lands the renumber.

## Validation (orchestrator-owned)

- [ ] Harness + `luacheck` floor on the landed tree (designer lane is touching
  `option_tables.lua` + `config_presets.lua` concurrently — re-run after merge).
- [ ] Mutation proofs on `/tmp/opencode` copies per standing rules for any
  order/copy edit (orders are sort keys: prove the re-sort renders).
- [ ] In-client confirmation for: D-O1 resequence, W-O1 renumber, R-M1 new
  toggles' hide-on-false behavior, X4 per-class format examples, H-C1 rename
  (name change while engine unwired — confirm no gather starts reading it).
- [ ] Re-check `tests/options_load_state.lua` §4c scope + §12 template ids +
  §13 pins after any fix lands (pins encode today's真相).
