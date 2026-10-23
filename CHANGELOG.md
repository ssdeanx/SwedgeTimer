# Changelog

## [2.1.1]

### Added

- One universal build for every supported client family, selected by per-flavor TOC dispatch:
  Classic Era / Season of Discovery (11509), TBC Anniversary (20506), WotLK Titanforge (38002),
  WoW Forever (16001) and Retail (120100, 120105).
- Paladin seal twisting: twist window band, attempt/success feedback, lag calibration and
  an impossible-twist warning, driven by the live combat log on the classic client line.
- Paladin next-action guide: an on-screen prompt (Crusader Strike / Command / Blood / twist)
  with HOLD/RIDE overlay, rotation text and cooldown swipes; draggable and lockable.
- Twist Practice trainer: a self-contained simulation of seal twisting with its own
  control panel, `/st practice`, and TWIST!/MISS result feedback.
- Shaman spell-weaving assist: breakpoint marker, cast spark and clip warning for
  Lightning Bolt, Chain Lightning, Healing Wave, Lesser Healing Wave and Chain Heal,
  including Maelstrom Weapon stacks and live haste.
- WoW Forever support: the addon now drives its swing timers from the client's native
  PLAYER_SWING events on that client (no classic combat log required).
  Twisting attempt/success scoring stays classic-line-only (no combat log on
  Mainline-code clients): on WoW Forever the twist band and next-action guide run
  normally while the hit-rate badge shows a "twist scoring: classic-line only"
  notice instead of a 0/0 score (UNCONFIRMED in-client).
- Warrior, Druid and Hunter on-next-attack awareness: Heroic Strike / Cleave, Maul and
  Raptor Strike queue colours plus insufficient-rage indication where applicable.
- Hunter queued Steady Shot detection (opt-in, disabled by default).
- Sourced durations from LibClassicDurations where the library exists (Classic Era and
  TBC Anniversary), with hardcoded fallbacks everywhere else.
- A LibDataBroker-1.1 data source publishing the current swing timer for broker displays.
- An offline verification harness (`bash tests/run.sh`): syntax, per-client profile smoke
  tests, per-module state suites, TOC integrity, static wiring parity and luacheck.
- Mainline-client probes for spell knowledge (`C_SpellBook.IsSpellKnown`) and spell range
  (`C_Spell.IsSpellInRange`), consulted after the classic globals so rank resolution and
  out-of-range tinting work on Retail and WoW Forever; range keeps the 1/0/nil contract.
- Melee-weave proximity bar (`weave_range.lua`, default OFF): vertical fill plus yards
  label driven by the existing range poll; uses exact per-yard `UnitDistanceSquared`
  readings where the client exposes them (Era, TBC Anniversary, Titanforge, Retail,
  WoW Forever) with band fallback elsewhere.
- WoW Forever path: swing-engine reader hardened (missing/throwing speed reads keep
  cycles on schedule); probe gating, 3-return shape, C_Spell rank fallback,
  UnitDistance secret fallback, LRC fallback and swing-gated guides all verified.
- Retail path: all five guide engines return the empty display shape on RETAIL (defense
  in depth over swing-gating); HUD/rotation/design/options work with static bars.
- `/st diag` reports the `C_Secrets` secret-value restriction predicates (cooldown, aura,
  power, stats, cast) when the client exposes them, and `api=no` when it does not.
- TBC Anniversary guide models: hunter Kill Command / Multi-Shot weave / Bestial Wrath /
  Rapid Fire prompts (all TBC-gated, steady timing untouched); warrior Bloodthirst /
  Whirlwind cooldown rules with HS rage floor and Execute reservation (cleave slot
  replaced); paladin Judge-fit and Crusader-debuff cues, Consecration single-target
  suppression, CS-delay default 1.7s to 0.9s; shaman Maelstrom-gated weave markers,
  Stormstrike delay-if-fishing-Windfury, Fire Nova / Earth Shock slots and a totem-twist
  timing model; druid TBC chain (Rip at 4+CP expiry-only, no Rake, 40/42 energy gates,
  long-fight Rip over Bite, powershift SHIFT hold). Other clients byte-identical.
- TBC Anniversary completion: 0.05s player-aura poll (UNIT_AURA is unreliable on TBC);
  judgement marker line, standalone seal icons with cooldown swipes, twist-success glow;
  cooldown HUD slots + rotation text for hunter/warrior/druid/shaman with options and
  defaults; practice mode timeline, rotation display, keybind capture, haste toggles,
  rotation selector, proc icons.
- Classic Era correctness: hunter Aimed Shot prompt + Multi weave with Steady Shot gated
  off (no such spell on Era); druid Mangle gated off with an Era Shred/Bite/powershift
  chain; warrior Era fury (BT/WW, HS floor 30 + 2.5s buffer, Execute spam); paladin
  Era seals (SoR twist position, no Crusader Strike, Hammer of Wrath filler); shaman
  Maelstrom markers/rules enabled by observed aura (SoD rune) instead of family, so
  Era-base stays silent. Other clients byte-identical.
- Per-class completion: hunter Aimed Shot HUD slot + default + toggle; shaman totem-twist
  timing model live on TBC (GetTotemInfo wrapper, commit stamp + air-slot poll);
  warrior Rampage badge (stacks + upkeep window) with default + toggle; paladin Hammer
  of Wrath filler icon (8th guide slot); druid bear chain assessed and pinned per client.
- Wrath (Titanforge) + SoD min/max: per-class branches (hunter MM/SV + Chimera;
  warrior fury/arms + SoD runes; paladin FCFS + Exodin; druid SR/TF/Berserk + SoD;
  shaman MW5-only + Feral/Fire Ele/Magma/Lava Lash), Retail engine gates, practice
  scoring (grades, session score, persistent bests), TBC micro-details + Forever
  adaptations per class (effective weapon speed, HS-cancel, Slam-safe band, twist
  calibration, energy-tick phase, WF ceiling; Hawk/Sniper, Bloodthrill/Victory Rush,
  Twist-of-Light, Shifting Power, Farseer haste).

### Changed

- All timing now runs on a single aligned high-precision clock behind the compatibility
  layer; every cross-client API access goes through one compat module.
- Spell, aura, cast, cooldown and haste reads are normalised across the classic and
  Mainline-code client families.

### Fixed

- Warrior: the rage-vs-queued-cost colouring never ran because its event was never
  registered; Blood Surge glow could churn and double-release its pooled frame.
- Casting within the first seconds after a reload could error on the spellcast, current-cast,
  GCD and equipment-change handlers before the bar frames existed.
- LibRangeCheck-2.0 could be dereferenced while its checkers were still nil, and the
  melee checker could fail to resolve at all; both paths are now guarded.
- Shaman: the cast spark could jump backwards when a cast outlasted the remaining swing.
- Stale queue colours after combat (warrior, druid, hunter, shaman) and a shaman cast that
  a wipe interrupted without an end event.
- Paladin: the next-action guide read player mana through a bare global that modern clients
  may strip, and two twist timestamps used a raw clock instead of the compat clock.
- Retail / WoW Forever: restricted ("secret") readings could raise Lua errors in the
  cooldown, power, health, aura, cast, haste, attack-speed and inventory paths; every
  compat wrapper (plus LibGlobalCooldown, the Forever swing engine and the class
  consumers) now degrades to the documented unknown/idle shape and the swing engine keeps
  its scheduled cycles, with identical behaviour for unrestricted reads and on classic
  clients.
- bars.lua: the latency and GCD-length refresh walked a hardcoded three-hand list, so
  post_init crashed on every login for the single-hand classes (paladin, druid); it now
  walks the hands that exist. A duplicate `convert_color` in bars.lua shadowed the
  canonical converter and silently flattened every 0-255 colour to black.
- Hunter: the Multi-Shot cast-grace matcher indexed its name cache before the client's
  spell data had answered, crashing on a cold cache; the lookup is now guarded.
- LibRangeCheck-2.0: the `LEARNED_SPELL_IN_TAB` / `PLAYER_TALENT_UPDATE` registrations are
  guarded with `C_EventUtils.IsEventValid` (registering an unknown event throws on modern
  clients and aborted the library's activate()). Upstream 2.0 is deprecated; the guard
  mirrors the maintained fork LibRangeCheck-3.0, and `tests/secret_guard_state.lua` pins it
  against re-vendoring.
- LibRangeCheck-2.0's internals are hardened for the Mainline clients the event guard
  re-enables: the classic spellbook globals (`GetNumSpellTabs` / `GetSpellTabInfo`) and the
  `IsSpellInRange` / `CheckInteractDistance` reads no longer throw when the client dropped
  them, and the range poll has a dead-man that disables range checking with one notice
  instead of erroring every interval (`tests/lrc_guard_state.lua` pins both).
- TBC Anniversary Hunter Swing Engine: `LibClassicSwingTimerAPI` expansion level detection
  now correctly detects TBC Anniversary (`LE_EXPANSION_LEVEL_CURRENT == nil` in Lua UI space;
  `GetClassicExpansionLevel() <= LE_EXPANSION_BURNING_CRUSADE` / `WOW_PROJECT_ID == 5`),
  properly initializing the `ranged_swing` and `next_melee_spells` tables.
- Auto Shot & Steady Shot Interaction: Added Steady Shot ranks (34120, 25258) to
  `noreset_swing_spells` in `LibClassicSwingTimerAPI` so Steady Shot casts never reset the
  ranged cycle. Steady Shot can safely land within the 0.5 s Auto Shot cast window (red zone)
  without clipping Auto Shot, provided it finishes before the auto shot releases.
- Combat Log Noise Reduction: Added source/dest GUID filtering to `ST:COMBAT_LOG_EVENT_UNFILTERED`
  and `LibClassicSwingTimerAPI:COMBAT_LOG_EVENT_UNFILTERED` to only process events involving the
  player or current target/enemy, filtering out >95% of extraneous raid/combat noise while
  safely preserving incoming PARRY haste on the player.
- Hunter Bar Defaults & Visibility: Set Hunter `mainhand`, `offhand`, and `ranged` bar presets to
  `show_condition = "either"` and `require_in_range = false`, preventing swing bars from hiding
  or freezing at 1px when out of range or when rangefinder checks lag.
- Clock Drift & Progress Skew: Aligned CLEU event timestamps with the monotonic
  `CanonicalGetTime()` clock domain (`_cleuClockOffset`) and clamped swing duration and progress
  calculations in `bars.lua` and `classes/hunter.lua` so `ends_at` strictly leads `start`.
- Code Quality & Nil Safety: Guarded all nil-check warnings in `bars.lua` (`set_gcd_marker_positions`,
  `on_bar_active`, `on_bar_inactive`, `set_gcd_width`, `set_deadzone_width`, `set_bar_texts`,
  `set_bar_color`) and `main.lua` (`ST:show_bar`), fixed `offSpeed` global variable leak in
  `LibClassicSwingTimerAPI.lua`, fixed `ui.practice_class_order` nil guard and `ui.toggle_timeline`
- Cross-Class Bar Audit & Ranged Presets: Audited bar enable flags, weapon probes, and visibility gating
  across Warrior, Paladin, Rogue, Shaman, and Druid. Aligned Rogue and Warrior ranged bar presets to
  `require_in_range = false` (matching Hunter and `ST.bar_defaults`), ensuring manually enabled ranged
  bars are never unexpectedly suppressed by range-checking failures or melee proximity.

### Guidance, HUD and design mode

- Cooldown HUD (ported from the archived build): a slot row with cooldown swipes, GCD dims,
  desaturate-on-cooldown, mana/out-of-range tints, proc glow and a trinket on-use/proc/ICD
  state machine; a per-class slot registry lets every class plug in its own abilities.
- Standalone rotation label (four formats, alignment anchors, fonts/outline/colour,
  visibility keys, drag/lock) and sound-preview dropdowns in the twist-sound options.
- Design mode: `/st design` draws a snap grid and alignment guides over every element
  (bars, HUD, rotation label, next-action guide, practice panel) with drag, double-click
  reset, and temporary lock override that restores each element's lock on exit.
- Next-action guides for warrior, druid, shaman and hunter on the paladin guide's provider
  contract (each with a pure decision engine and an offline suite), and the rogue guide on the
  same contract. The guides first shipped disabled "until verified in client"; that staging
  is over — **all six guides now ship enabled by default** (`nextaction_enabled = true` in
  every class default, `config_presets.lua`), and each can still be turned off per class.
- Class visuals: shaman breakpoint markers top/bottom, offhand cast spark, Windfury ICD strip,
  Flame Shock debuff bar, Stormstrike/Shamanistic Rage badges and shield-charge row; hunter
  Auto-Shot cooldown sync, auto-repeat gating, movement safe-stop maths, hidden-window cast
  bar with latency end-slice and clip tint, 4-state range helper, Rapid Fire bar and aspect
  icon; druid energy-tick column, form label and Mangle/Rip/Rake debuff bars; warrior Sunder
  Armor (with stacks), Deep Wounds, Rend, Thunder Clap and Demolition Shout bars, Shield
  Block bar, Slam cast bar and the Overpower flash (classic combat log).
- Hardening: the last direct cross-client global reads moved behind compat wrappers, the
  LibRangeCheck checker fallback/guards were tightened, the practice panel retries its
  frame creation if the addon finishes initialising mid-combat, and the guide engine's
  per-tick closure allocation was hoisted.

- Retail / WoW Forever: the 120105 (Retail 12.1.5) interface is now advertised
  alongside 120100, so the addon loads as 12.1.x (120100, 120105) with no
  out-of-date flag on either Retail patch (UNCONFIRMED in-client).

### Build-out round + hardening (2026-10-17, verified offline, UNCONFIRMED in-client)

- Bloodlust / Heroism lust window: `st.api.scan_player_aura` single-pass 1..40
  HELPFUL scan over ids 2825 / 32182 (TBC+ families only; Era/UNKNOWN closed),
  consumed by the hunter Steady-spam cue (H2, 0.5 s throttle) and the paladin
  twist-window narrowing (P3, 0.6x scale, nil-safe passthrough).
- Per-tick budget audit (C4): opt-in `/st diag` tick counters
  (`diag_tick_counters`, default OFF, zero per-tick cost when off, applies at
  next login/reload).
- Unified swing-safe overlay service (C3) + snap-to-row template registration
  (C6) + generic pips widget (D3); design mode gains snap templates and
  mouse-anchored dragging (nil = existing grab-offset behaviour).
- Paladin: live twist hit-rate badge (combat-only, optional session persist),
  JotC uptime mini-bar (21183, 20 s max-rank melee refresh), Art of War +
  Exorcism overlap pulse, seal-icon texture latch, adaptive CD icon row
  (Avenging Wrath / Divine Shield / Hammer of Justice / BoP / Holy Wrath /
  Lay on Hands + racial slot; Holy Wrath ranks and the racial list UNCONFIRMED).
- Warrior: bank cue (nil-off), composite BT/WW rage gate with HS reserve,
  Rampage tier badge, Battle Shout badge, Overpower glow-lifecycle fix, four
  arms/SoD HUD slot toggles (Rend / Mortal Strike / Bladestorm / Raging Blow,
  shipped true = no visible change).
- Hunter: lust-driven Steady-spam cue, Feign Death display reset, Readiness
  Rapid Fire refresh, safe-to-move cast zone, Bestial Wrath / Frenzy pet badges,
  Aimed Shot re-point prompt.
- Shaman: Stormstrike nature-vuln bar (17364, 12 s), Windfury-fishing SS HOLD
  tint + final-fraction wash, MW5 Lava Burst choice (SoD rune-gated) + Flame
  Shock collision guard, Rockbiter badge, shield-charge 3-charge standard
  fallback; round 2 adds 2-3-stack weave markers with safe-start zone band,
  per-spell clip state, Flurry ICD (0.5 s) + DW sync badges.
- Druid: Tiger's Fury / Berserk HUD slots (glow when ready), combo-point pips,
  EMA time-to-die, energy-cost countdown, GCD tick overlay, Omen glow,
  Maul badge, name-based Tiger's Fury resolution.
- Practice: generic scenario harness (C1) + P5/H5/W6/D7/S7 drills, panel reset
  button (re-anchors immediately), timeline drag persistence + close button,
  action-input paths for all four scenario shells.
- Enemy swing bar (opt-in, default OFF): hostile-target mainhand swing bar on
  the classic line only (Era / TBC / Wrath / Cata / Mists); inert on
  Forever / Retail / UNKNOWN.
- Options: 27 round toggles + 4 warrior slot toggles wired, all nil-safe
  (nil = OFF except hide-on-false HUD slots shipped true); `hunter_multi_target`
  ships with its toggle only — the multi-target engine is a future round; the shipped
  `hunter_multi_target` copy reads "Multi-target mode (manual, not wired yet)".
- Enterprise-grade wave: options-file warnings wired, practice panel/timeline/
  scoring fixes, HUD provider-hidden slots now hide (no stale live-looking
  icons) with hidden-slot row reflow on hidden-flip outside combat (deferred
  only under lockdown; closed by the hud-reflow lane,
  bench/buildout_hud-reflow_2026-10-17.md), practice
  rotation + timeline design targets (registry 7 -> 9), rest-of-tree warning
  wiring per the trace-and-wire rule.
- Hardening (oracle R1-R4): Anniversary string-payload fallbacks on the paladin
  twist-success and warrior special-ability paths (numeric path byte-identical;
  owner `/dump` of the CLEU spellId slot type still settles it); secret-hole
  scan truncation closed in compat + paladin + warrior + shaman + druid aura
  loops (full 1..40 walks, nil = no match at this index); lust gate
  standardised on `st.lust_supported == true` (closed-on-unknown).
- Harness: 35 steps, 0 failed; luacheck 2 warnings / 0 errors (both KEEP-ruled
  standing). Every behavior above is verified offline only — the in-client
  checklist in TESTING.md is the owner acceptance pass.

### Rogue sixth class (2026-10-19, verified offline, UNCONFIRMED in-client)

- Skeleton + wiring: NEW `classes/rogue.lua` (module open, empty id tables,
  `HUD_SLOTS` + `get_hud_state`, `guide` provider returning
  `inputs_unknown=true`, `on_bar_update` driving guide + HUD, `on_combat_exit`
  preserving the mainhand record) appended to all 7 TOC load orders after
  `classes\warrior.lua`; `ST.ROGUE.defaults` class keys (all opt-in OFF);
  `ST.class_opts_funcs.ROGUE` options section; `tests/rogue_state.lua` suite.
- Pure engine: NEW root `rogue_guide.lua` (pool-vs-spend on data-driven 65/85
  pooling bands, Rupture-vs-Eviscerate decider on EMA time-to-die, per-client
  Envenom rule tables, EA-duty refresh, Shiv upkeep, Thistle-Tea deficit cue,
  `inputs_unknown` contract) with `tests/rogue_guide_state.lua` (206 checks).
- Cues + provider: proc-aware 2 s energy-tick predictor (Combat-Potency 15-energy
  grants never re-anchor; ambiguous tick hides, never guesses), energy-tick spark
  - pooling tint, Era-only post-mainhand-swing 0.1–0.2 s Sinister Strike window
  (sword mainhand only; never on TBC+), weapon-swap band ("swap: GCD + swing
  reset"), mainhand/offhand poison reminder (presence only — charges UNCONFIRMED,
  unrendered), live HUD slots (SnD/Rupture/EA/AR/BF/Tea/Kick) + POOL/NOW guide
  mapping with aura/energy/CP-unknown "…" rule.
- Practice drills: `rogue_energy_pool` (cast-start fraction vs tick marker,
  S..F bands, clip is F, nil tick unscored) and `rogue_ss_window` (Era 0.1–0.2 s
  post-swing offsets, ideal 0.1 s, F outside) scenarios; options copy states the
  unknown-hides rules for energy/tick, cues and the guide.
- Compat probes: `api.GetItemInfo` / `api.GetItemCount` / `api.GetItemCooldown` /
  `api.GetWeaponEnchantInfo` / `api.UnitGUID` moved behind probe chains in
  `compat.lua` (C_Item-first, classic fallbacks, secret/throw-safe unknown
  shapes); zero `rawget` probes remain in `classes/rogue.lua`. Latent fix: the
  offhand-enchant presence read is the 5th `GetWeaponEnchantInfo` return (four
  values per weapon slot), not the 4th — the 4th is the mainhand enchant id, so
  the old read could never show the poison reminder on a real client
  (`bench/buildout_rogue-compat_2026-10-19.md`).
- Options panel parity: SS-window / weapon-swap / poison-reminder toggles +
  colours, `rogue_ea_duty` opt-in, six guide thresholds pinned to the pure
  engine defaults, HUD slots, POOL/NOW copy (`bench/buildout_rogue-options_2026-10-19.md`).
  The ten Skeleton-lane cue keys (`show_rogue_snd_cue` et al.) were REMOVED by
  the rogue-parity lane (defaults + widgets + header/desc gone; absence pinned
  in `tests/rogue_state.lua` §§2/3 and `tests/options_load_state.lua` §9):
  the HUD slots + guide actions already cover every upkeep state the duplicate
  bar presentation promised, so it would have added no signal
  (`desks/rogue-parity/`). Harness floor held throughout: 37 steps, 0 failed;
  luacheck 2 warnings / 0 errors.
- Post-section landings: `ST.ROGUE.get_rotation_key` rotation-label provider
  (hunter shape; `desks/rogue-parity/`); ROGUE in `diag.lua`
  `PROVIDER_CLASSES` with guide/HUD pins (`desks/rogue-diag/`); Era
  Sinister Strike window ships RED and visible by default per owner order
  (`show_rogue_ss_window` true, `rogue_ss_color` red; `desks/rogue-redzone/`);
  warrior unmatched-payload counter with notice threshold
  (`WARRIOR_PAYLOAD_NOTICE_AT`; `desks/five-class-gaps/`); rogue-erroraudit
  hardenings F1/F2/F4/F5/F6 (NaN-safe number funnel, `GetItemCount`
  non-number check, POOL_BANDS / rule-order / rules-4-5-unknown-family pins;
  F3 accepted as documented residual —
  `bench/rogue_erroraudit_2026-10-19.md`, `desks/rogue-auditfixes/`).
- Rotation audits vs sims for all six classes (bench/*_rotation_audit_2026-10-19.md),
  followed by rotation-fix + follow-up waves: per-client EA/Tea/Shiv/builder rules
  (rogue), ICD discipline + SoD 200ms window (paladin), ww_ids→1680 + TBC HS ranks +
  hamstring engine (warrior), rule-7 opt-in + SoD slots + shock-capped ES (shaman),
  LnL arms + Serpent guard (hunter), trick/pooling + RipCP override (druid).
  Harness floor held throughout: 38 steps, 0 failed; luacheck 2/0.
- Operator-ruled cuts: Victory Rush SKIP (inert-by-default stands), hunter lust
  branch CUT (sim-faithful; alt-later opt-in documented), fight-remaining CUT,
  hawk-count CUT (probe-gated). W2 Battle Shout built fully; rogue H6 wait-HOLD +
  SoD ENVENOM rule wired; Blood Frenzy rune 412507 confirmed in-game by operator.
- Options-complete: per-class HUD template select (18 templates + Custom fallback),
  wowsims synergy copy in all 6 panels, LnL badge + Cold Blood + mana-threshold +
  RipCP widgets with live consumers; hard-wait WAIT render; shaman twist-mana feed;
  rogue 1CP/5CP Rupture DATA; druid FF fish rules + Claw slot; SoD paladin variants
  (seal-stacking, Shockadin, SoD-wrath) per fetched APLs; /st diag verbose gains
  id-resolution (67 wanted ids) + in-memory error log. All offline-verified,
  UNCONFIRMED in-client; see bench/live_test_script_2026-10-19.md.

### Final hardening (2026-10-19, verified offline, UNCONFIRMED in-client)

- TBC-name / Era-id spell resolution across all classes with both-directions pins; compat hardened (C_SpellBook probes, CLEU mainline gate, shapeshift fallback); missing-class stubs for Monk/Demon Hunter/Evoker on Retail.
- Hunter melee-weave prog (distance band + LibRangeCheck drive, opt-in toggle) and trap tracking with Clever Traps handling.
- Usable-only trinket HUD (passive/unknown hide); running-GCD swipe on rogue; Claw HUD slot on druid; paladin guide→HUD slot mirror; warrior Sunder/Rend/stance-dance/hamstring rules.
- Guide/HUD/rotation-label/practice drivers contained under one error-quarantine discipline; `/st diag verbose` carries wanted-id resolution + in-memory error log.
- Settings pass: per-class copy/order/alignment, option for every shipped feature; HUD template gallery per class from researched WeakAura layouts.
- Release readiness audited (bench/release_audit_2026-10-19.md): versions 2.1.1, TOC coverage, harness 38/0, luacheck 2/0.

### Practice/designer wave (2026-10-19; closes proctor G5)

- Top-level Practice page (`ST.opts_table.args.practice`, order 1.46): Start/Stop toggle on the same `st.practice_ui.toggle` session as `/st practice` and the class-panel buttons; Simulation rows (weapon-speed override, AW-macro pot/SoB, DST, queue window, BL delay) with live `practice_ui` consumers; rotation/timeline status text; feedback mirrors; desc enumerates all six drills (verified offline, UNCONFIRMED in-client; `bench/paladin_practice_designer_2026-10-19.md`, `tests/paladin_state.lua` page pins).
- Paladin drill deltas: twist sim + AW-combo drill (`paladin_twist`, `paladin_aw_combo`) on the shared session with start seeding (dst/bl/queue, nil = current defaults) and the archive-rule AW macro (pot sets the buff directly, SoB casts the full seal when the GCD is free) (verified offline, UNCONFIRMED in-client; `tests/paladin_state.lua` 520/520, `tests/practice_state.lua` registry pins).
- Warrior Execute drill: `warrior_execute` (20% HP threshold, BANK entry-rage bands S..F) grades live Execute-range entries with no sim of its own, plus the post-fight WarriorExecuteReport frame (verified offline, UNCONFIRMED in-client; `tests/warrior_state.lua` W6 pins, `tests/practice_state.lua` execute_phase pins; H6 ruling: report/live-log design stands, copy describes it honestly).
- Hunter forced-move drill: `hunter_forced_move` (cast inside a window is F, overrun into the next window is C, margin bands B/A/S; movement itself stays in-client) with panel shot icons casting simulated Steady/Multi/Aimed plus the shot report frame (verified offline, UNCONFIRMED in-client; `bench/hunter_practice_designer_2026-10-19.md`, `tests/hunter_state.lua` 969 §§P-U).
- Rogue drills: `rogue_energy_pool` (spend before the 2 s tick marker, clip is F, nil marker unscored) and `rogue_ss_window` (Era-only 0.1-0.2 s post-swing offsets, ideal 0.1 s, F outside; TBC+ runs pool only) (verified offline, UNCONFIRMED in-client; `bench/buildout_rogue-pd_2026-10-19.md`, `tests/rogue_state.lua` 678 §15).
- Druid powershift drill: `druid_powershift` (shift inside the 20-energy rule, fixed 40-refund Furor-5/5 sim constant, S..F bands) with the DRUID options Practice block and shared-session bridge (verified offline, UNCONFIRMED in-client; `tests/druid_state.lua` 602 §§30-35).
- Shaman weave drill: `shaman_weave` on `weave.lua` marker/clip math (safe-start margin bands S..D, clip is F, nil without the model) with the SHAMAN 5.x Weave Practice block (verified offline, UNCONFIRMED in-client; `bench/shaman_drill_designer_2026-10-19.md`, `tests/shaman_state.lua` 590 §§33-36).
- Both-ways start for every drill (`/st practice`, class-panel toggle, top-level Practice toggle into one session; panel icons + keybinds cast simulated spells) with S..F grades into the shared running score and persistent bests (verified offline, UNCONFIRMED in-client; `tests/practice_ui_state.lua` scoring/bests pins, `tests/practice_state.lua` 8-scenario registry pins).
- Designer: `seal_icons` + `success_text` descriptors (archive ELEMENTS shape; drag detaches, double-click reset re-attaches) and `practice_hunter_report` + `practice_warrior_report` descriptors (available only while shown); registry 3 bars + 2 paladin + HUD/rottext/NAG/practice panel/rotation/timeline + 2 reports = 13 design targets — **14 on a druid**, which registers the Combo Points pips as a fourteenth (verified offline, UNCONFIRMED in-client; `tests/designmode_state.lua` count/title/by_key pins; the druid's own pips design key in `classes/druid.lua`).
- Reconcile: 6 SODOPT presence flips, design count 9->11 pins, hunter `H.` -> `ST.HUNTER` qualification, druid drill routing (verified offline, UNCONFIRMED in-client; `desks/reconcile-pd/`, 38/0 + 7/7 mutation kills on `/tmp/opencode` copies).
- Hardening: drill tick/cast quarantine, GCD nil-restore, sync fail-closed routing, toggle/post_init guards, `use_shaman_drill` accessor, report lockdown guard, ROGUE_DEBUG removal, top-level desc rewrite; G1-G3/G6 behavior pins landed, G4 stays filed (verified offline, UNCONFIRMED in-client; `desks/hardening-pd/`, 38/0 + 7/7 mutation kills on `/tmp/opencode` copies).

### Rotation scenarios + per-class drills (2026-10-19, verified offline, UNCONFIRMED in-client)

- A shared **rotation scenario** engine (`practice.lua`): a run of ten GCD-chain decisions
  (`H.ROTATION_RUN_STEPS = 10`) where each step asks the class what its rotation wants and
  grades the cast. The four outcome classes are `correct` / `out_of_order` / `miss` /
  `unknown`; a correct decision grades S, a wrong or missing one grades F, and an **unknown
  decision records no attempt at all** (never a wrong grade). The run band is S 0 mis-picks /
  A 1 / B 2 / C 3 / D 4-5 / F 6+ on the mis-pick count (a miss counts as a mis-pick) —
  `[DESIGN]` addon policy, not a sim number (`bench/practice_scenario_engine_2026-10-19.md`).
- A **practice mode** select on the Practice options page: `class` (the shipped per-class
  session, the default), `scenario` (the class's own rotation, end to end) and `drills` (the
  class's focused drill list, one button each). A class that ships no scenario or no drills
  refuses that session with a clear message — it never falls back to another class's drill
  (`bench/practice_scenario_engine_2026-10-19.md` §2.2 and §3).
- **All six classes ship a rotation scenario**, and each answers from its own guide engine
  (`ST.<CLASS>.practice_scenario_step`), so the scenario teaches what the guide teaches and
  the two can never disagree. The six scenario ids: `paladin_rotation`, `hunter_rotation`,
  `shaman_rotation`, `rogue_rotation`, `druid_rotation`, `warrior_rotation`
  (`practice_ui.lua` `PRACTICE_DRILL_KEYS`; `bench/class_features_drills_2026-10-19.md` §2).
- **25 per-class drills** ship, three to six per class, each grading a different skill
  (baseline resource behaviour is not a drill): paladin `paladin_fcfs_priority` /
  `paladin_prepull` / `paladin_judge_fit`; warrior `warrior_core_order` /
  `warrior_ww_delay` / `warrior_sunder_upkeep` / `warrior_execute_burn` /
  `warrior_hs_queue` / `warrior_prepull`; hunter `hunter_shot_order` /
  `hunter_weave_clip` / `hunter_kill_command` / `hunter_prepull`;
  rogue `rogue_finisher_order` / `rogue_cp_finish` / `rogue_snd_upkeep` / `rogue_opener`;
  druid `druid_finisher_order` / `druid_powershift_rework` / `druid_roar_upkeep` /
  `druid_bite_execute`; shaman `shaman_enh_priority` / `shaman_mw_weave` /
  `shaman_stormstrike_hold` / `shaman_totem_upkeep`
  (`bench/class_features_drills_2026-10-19.md` §§2.1-2.6; the per-class class files;
  the warrior's two 2026-10-20 additions — `bench/warrior_hs_queue_2026-10-20.md` §2.3,
  `bench/warrior_apl_utility_live_2026-10-20.md` §5).
- The eight **built-in** drills stay registered for backward compatibility; three are
  **superseded** by a class drill that owns the same skill (`druid_powershift` →
  `druid_powershift_rework`, `shaman_weave` → `shaman_mw_weave`, `warrior_execute` →
  `warrior_execute_burn`) and their grading is delegated to the class drill, so the retired
  truth never grades a player attempt. The class session wrappers now start the class's own
  drill, and the shaman's namespace-alias stopgap is gone
  (`bench/practice_scenario_engine_2026-10-19.md` §5; `bench/superseded_wrappers_2026-10-19.md`).

### Practice gamification (2026-10-19, verified offline, UNCONFIRMED in-client)

- **XP, levels and renown.** XP per attempt is the live grade-point value (F earns 0 — a
  miss costs nothing, it just does not earn); the level curve is `floor(100 * n^1.35)`, the
  cap is level 50 per class and past it a **renown** counter increments. Progression is
  **per class** plus a global account total, and a drill's XP is capped per day at 3x its
  median attempt XP, so one drill cannot be farmed for infinite levels
  (`bench/practice_gamification_design_2026-10-19.md` §2;
  `bench/buildout_practice_gamification_foundation_2026-10-19.md`).
- **Per-drill mastery with tiers.** A drill's mastery is the recency-weighted accuracy over
  its last 100 attempts (half-life 30); below 20 attempts it reads **Unranked** (one lucky S
  never grants mastery). The tiers are Unranked -> Bronze (60% / 20 attempts) -> Silver
  (75% / 50) -> Gold (85% / 100) -> Platinum (95% / 200)
  (`bench/practice_gamification_design_2026-10-19.md` §2).
- **Streaks.** A session streak (consecutive non-F attempts), a lifetime best streak, and a
  daily streak of consecutive calendar days with a completed session — a missed day
  **freezes** the daily streak, it never resets it (the operator's no-punishment ruling)
  (`bench/practice_gamification_design_2026-10-19.md` §2 and §9).
- **Achievements.** A static, data-driven id table — `first_s`, `perfect_ten`,
  `hundred_attempts`, `all_drills_gold`, `level_10`, `week_streak`, `ten_hours` — evaluated
  on every session end; each unlock fires a notice once
  (`bench/practice_gamification_design_2026-10-19.md` §4;
  `bench/buildout_practice_gamification_foundation_2026-10-19.md`).
- **An unlock registry** with three kinds — achievement, cosmetic and level-gated harder
  drill variant — and one hard rule: an unlock never changes how an existing drill behaves,
  a variant is registered as its own scenario. The seven achievements are registered; the
  cosmetic and drill-variant catalogues are **empty in this build** (the registry is the
  mechanism, not a shipped catalogue)
  (`bench/practice_gamification_design_2026-10-19.md` §5;
  `bench/buildout_practice_gamification_foundation_2026-10-19.md`).
- **Stats.** Lifetime aggregates per class and global: runs, attempts/hits/misses and
  accuracy (lifetime, rolling-last-20, last session), time active (counted only while a
  session is live, never while the panel sits idle), best session score, best single grade,
  best streak, XP/level/progress toward the next level, a per-drill table, and the last
  **50** sessions as a bounded ring buffer
  (`bench/practice_gamification_design_2026-10-19.md` §3;
  `bench/buildout_practice_gamification_foundation_2026-10-19.md`).
- **A Progress options page** (order 1.47, next to Practice): level, an XP bar, the
  per-drill mastery table, the achievements list, the stats summary, the all-classes line, a
  button that opens the stats frame, and a two-step reset with a cancel
  (`bench/buildout_practice_progress_ui_2026-10-19.md` §2).
- **A stats frame** with the accuracy **sparkline** over the last 50 sessions, the per-drill
  table, the per-class table and the session history (newest first, wheel scrolled with a
  tracking thumb), plus a Scope button that cycles the classes that have data and the
  account scope (`bench/buildout_practice_progress_ui_2026-10-19.md` §1).
- **A panel level badge**: level ("Lv 3", or "Lv 50 +2" past the cap), the XP into the level
  ("80/100"), the level-progress bar and the session XP ("+80 XP"), drawn under the panel so
  it overlaps nothing. It ships **ON** — the operator's request for visible levels/XP is the
  gate for that default-visible change — and the Progress page carries the toggle that turns
  it off (`bench/buildout_gamification_visibility_2026-10-19.md`;
  `bench/buildout_options_pass_2026-10-19.md` §1 item 4, the HU-9 widget).
- **Persistence and repair.** Progress and stats live in `SwedgeTimerDB.profile.practice`
  with a schema version: a corrupt blob repairs itself on load instead of throwing, a blob a
  newer build wrote is left untouched, and saves are throttled (session end, level-up, and
  at most once every five minutes during a live session — never per attempt)
  (`bench/buildout_practice_gamification_foundation_2026-10-19.md`;
  `bench/buildout_practice_gamification_hook_2026-10-19.md`).
- Progress is **local-only**: this build ships no settings export/import surface, so a
  profile cannot be moved between machines
  (`bench/practice_gamification_design_2026-10-19.md` §6, corrected 2026-10-20).

### Audit fixes (2026-10-19, verified offline, UNCONFIRMED in-client)

- **The error-ring install (F1).** The `seterrorhandler` chain was never installed, so
  `/st diag` printed "errors none" as a *fact* when nothing could have been observed. The
  chain is installed once at init and removed again on logout, and the two empty states are
  now distinguishable: "errors none (handler installed, nothing thrown)" vs "errors not
  observed (no error handler installed)" (`bench/audit_fixes_2026-10-19.md` §F1).
- **The offhand handler (F2).** `PLAYER_TARGET_SET_ATTACKING` was registered but unreachable:
  `has_oh` was initialised false and never set again, so the handler always returned at its
  guard — and the test suite defeated the guard by hand, which is what hid the defect. The
  flag is now derived from the same offhand probe that fills the bar's weapon state, and the
  handler gained a `ST:has_hand("offhand")` guard: a paladin or a druid has an offhand weapon
  but no offhand bar, and without that guard the AceDB `**` metatable auto-creates a
  synthetic table and the colour read raises inside a live event handler
  (`bench/audit_fixes_2026-10-19.md` §F2).
- **The report's printer (F3) and the HUD's counter (F5).** The diag report's only output
  path was the bare global `print`; it now falls back to the addon's own chat printer and
  says so once, so a report that changed channel is never mistaken for one that never ran.
  The HUD's combat-log registration counter was write-only; the runtime diag line now reads
  it (`bench/audit_fixes_2026-10-19.md` §F3 and §F5).
- **Two dead helpers removed (F7, F11).** `ST:needs_gcd()` had no callers and its
  synthetic-table read was a trap (the GCD underlay is gated per hand in `bars.lua`); the
  seven `assert(event == event)` tautologies are gone, with the unused arguments named
  instead (`bench/audit_fixes_2026-10-19.md` §F7 and §F11).
- **The TBC name-vs-id resolution (F4).** The family spell resolver now answers
  `resolved` / `absent` / `unresolved` instead of collapsing "the client could not answer"
  into "this spell is not here". **Only `absent` latches a negative** (it is final);
  `unresolved` latches nothing and the next attempt asks the client again, behind a
  five-second backoff so a client that cannot answer never re-walks the rank table every
  frame. The druid and the warrior class latches moved onto the state API
  (`bench/f4_family_spell_id_2026-10-19.md`; `bench/class_f4_latch_2026-10-19.md`).
- **The base TOC (F6).** The base `SwedgeTimer.toc` no longer advertises a mainline
  interface: it is the classic-line fallback (11509, 20506, 38002), because the vendored
  `LibClassicSwingTimerAPI` registers a combat-log event at file scope and throws on
  mainline-code clients. The mainline flavour ships without that library
  (`bench/audit_fixes_2026-10-19.md` §"Still open"; the base toc's
  `## Interface: 11509, 20506, 38002`).
- **One shared error-isolation helper (F10).** The isolation contract (count -> report once
  -> quarantine after 25 -> the caller's own degrade) was implemented **six times** with six
  quarantine constants, and the copies had already diverged (one printed on every refusal,
  the other five printed once). A new root module `guard.lua` now owns it once — the shared
  entry points (`st.guard.run(owner, site, fn, ...)` and its `note` / `quarantined` /
  `refusal` siblings) — and the six call sites (`bars.lua`, `hud.lua`, `nextaction_ui.lua`,
  `practice_ui.lua` twice, `rotationtext.lua`) were migrated onto it;
  `st.guard.QUARANTINE_THROWS` is the only threshold constant left
  (`bench/f10_shared_guard_2026-10-19.md`).
- **The scenario-context crash.** The default scenario context raised on an undefined
  `SCENARIO_RESOURCE_KEYS` constant for the druid, warrior and shaman; the list is now a
  local, verified against the six classes' own `gather_guide_inputs`, and the lift can no
  longer crash (`bench/f10_shared_guard_2026-10-19.md`).
- **The class-module namespace fix (HU-7).** The pure half resolved the class module from
  the namespace table, but the class tables live on the AceAddon table — so the engine
  found no class module at all. The AceAddon table is resolved first now and the namespace
  is the fallback, which is what let the shaman's `st.SHAMAN = ST.SHAMAN` stopgap be
  removed (`bench/practice_scenario_engine_2026-10-19.md` §6;
  `bench/superseded_wrappers_2026-10-19.md` §1.3).

### Closure wave (2026-10-19, verified offline, UNCONFIRMED in-client)

- **The Wolfshead probe (druid).** `api.is_item_equipped(8345)` — a tri-state read (`true`
  worn / `false` readable-and-absent / `nil` unknown, never a guessed false) — is published
  as `inputs.wolfshead_equipped` and throttled to one read per second (it was ~380
  equipped-slot reads/s for an input no rule reads yet). It is a reserved plug-in point: the
  Furor half of the powershift basis is still unproven, so no rule consumes it
  (`bench/compat_probes_2026-10-19.md` §1.2; `bench/buildout_closure_triad_2026-10-19.md` §3).
- **The Serpent target scan (hunter).** `inputs.serpent_active` is no longer a hard-coded
  nil: it is a real three-state feed from a target debuff scan (the name "Serpent Sting"
  first, the sourced rank ids second), so the Chimera is withheld only when the sting is
  **known** to be down, and an unreadable debuff still allows the prompt
  (`bench/hunter_serpent_2026-10-19.md`).
- **Call of the Elements + the per-family Stormstrike (shaman).** The water-totem clock
  (client-sourced slot 3, tri-state: the seconds left, `0` for an affirmatively empty slot,
  `nil` for an unknown read) feeds a new 18th guide slot — `{ key = "coe", spell_id = 66842 }`
  — which fires on Wrath while the water totem has under 20 s left, plus a display-only HUD
  mirror that hides unless its toggle reads exactly true. The Stormstrike swipe fallback is
  now per family (Era 20 s / SoD 6 s / TBC 10 s / Wrath 8 s, 10 s elsewhere — no invented
  number) on both the guide slot and the HUD mirror
  (`bench/shaman_coe_ss_2026-10-19.md`).
- **The Flame Shock default is sim-exact.** `guide_flameshock_refresh` now ships **0**
  (every sim re-applies Flame Shock only when the dot is inactive) instead of 3, and the
  gather's stale `or 3` fallback was aligned to the same value — the shipped 3 shaved about
  three seconds off every Flame Shock dot
  (`bench/buildout_options_pass_2026-10-19.md` §2 item 3;
  `bench/buildout_closure_triad_2026-10-19.md` §2).
- **The Hemorrhage builder (rogue) + the swapped-id corpus fix.** The builder candidate
  chain is now `{ "Saber Slash", "Mutilate", "Hemorrhage" }` ahead of the dagger Backstab
  and the Sinister Strike fallback, with a family gate (Hemorrhage is an Era/TBC/Forever
  builder, never a SoD one — it never sits ahead of a rune the sim prefers) and
  unknown-hides (a name the client does not know falls through, never a wrong builder).
  The bench corpus had the TBC ids swapped: **26862 is Sinister Strike and 26864 is
  Hemorrhage** (`desks/rogue-hemorrhage/journal.md`;
  `bench/filed_closure_sweep_2026-10-19.md` §9-N1).
- **The Forever Echo and Holy Strike ids (paladin).** The two deliberately-empty Forever id
  tables now carry `1311703` (Echo of Command) and `1311704` (Echo of Righteousness), and
  Holy Strike `10333` is published as a plug-in point. All three are **web-confirmed,
  client-unconfirmed and name-anchored**: an id only counts when the client's own resolved
  name matches, so a wrong id leaves the input unknown instead of producing a wrong prompt
  (`bench/buildout_paladin_bs5_2026-10-19.md`).

### Scenario surface + APL utility layer (2026-10-20, verified offline, UNCONFIRMED in-client)

- **The scenario surface works now.** Two CRITICAL defects were **offline-invisible** and are
  fixed. The **paladin's** scenario mode graded nothing in-game: its own context builder was
  written for the twist simulation and served that shape to a live call, so every sim-shaped
  field was nil, the decision was nil and **every step was UNKNOWN** — no attempt, no grade,
  no XP. The builder serves both shapes now (the sim shape verbatim; the live shape from the
  class's own gathered guide inputs). The **drill list** answered UNKNOWN on every press for
  **five of the six classes**: the row built the context with no pick, and every pick-based
  grader answers nil without one (the hunter was the one class that worked — its grader reads
  the context's own pick). The drill-list row now carries the class's **actions** as the pick
  channel (`bench/paladin_scenario_surface_2026-10-20.md` §1;
  `bench/practice_ui_fixes_2026-10-20.md` §1).
- **The shaman's and the druid's own sessions are reachable again.** The supersession was
  checked before the shipped session, so the drill list won, the class panel's icons hit a nil
  session and were **silent no-ops**. The shipped session is checked first now (a class with a
  session of its own keeps it, and that session grades through the class's own drill), and any
  drill cast with no session is **loud** — it prints the reason and counts it
  (`bench/practice_ui_fixes_2026-10-20.md` §2).
- **The scenario row no longer leaks frames.** The row rebuilt its button set on every step and
  only hid the old buttons — roughly 200-300 hidden frames per run. The buttons are reused from
  the row's own pool now, so a rebuild is a pass, not a new set
  (`bench/practice_ui_fixes_2026-10-20.md` §3).
- **The rotation scenario is gated on a live swing engine.** The Retail client keeps the inert
  stand-in and cannot run a timed rotation, so the session is refused loudly — the refusal
  reads "Practice scenario is not available on this client (no live swing engine)."
  (`practice_ui.lua`) — and the Practice page's availability note carries its own, separate
  string: "The rotation scenario cannot run on this client (no live swing engine)."
  (`option_tables.lua`). Two strings for one behaviour. Only the *explicit* stand-in counts as
  dead — a client that has not reported its engine yet is unknown and is never blocked
  (`bench/practice_ui_fixes_2026-10-20.md` §4).
- **The drill counters die with the session.** They hung off the addon object, so a band's
  mis-picks survived into the next session and a drill decayed S → F for the life of the
  profile; the drill-list session owns its own identity and window now
  (`bench/practice_ui_fixes_2026-10-20.md` §5).
- **The twist minigame is the paladin's.** The twist drill leads the paladin's drill list (the
  flagship practice stays reachable from the paladin's panel), and a class that publishes no
  drills of its own and owns no twist drill is refused loudly ("No practice for this class.")
  instead of inheriting the paladin's minigame. The warrior is not one of them — it publishes
  six drills of its own (`bench/practice_ui_fixes_2026-10-20.md` §6; the operator's ruling;
  the warrior's own drill keys in `tests/warrior_state.lua`).
- **A hold is a decision; unknown is not.** The class contract grows an explicit hold
  statement. The engine grades a cast during a hold as an **illegal cast** (F — it counts as a
  mis-pick) and a correct hold records **no attempt** (no points, no streak, no mastery tick);
  a step with neither an action nor a hold stays UNKNOWN. The paladin (the twist RIDE window
  and the FCFS "nothing is ready"), the rogue (POOL), the shaman (RIDE / WAIT), the hunter
  (RIDE / HOLD) and the warrior (RIDE / HOLD) state their own holds. The druid's holds came in
  two shapes — nine spell-naming holds (a decision to *cast*) and one press-nothing hold
  (`RIDE`, the bear chain's queued Maul); the split is documented in the **Audit-fix wave**
  section below, which supersedes the earlier note that the druid stated no hold at all
  (`bench/shared_engine_bs8_2026-10-20.md` §1;
  `bench/class_hold_statements_2026-10-20.md` §2 — superseded by
  `bench/druid_hold_ride_2026-10-20.md` §7).
- **The APL utility layer.** Every class's rotation table now carries the sims' **full**
  priority list, not just the damage rows. Two rules apply cross-class: the **rotation** table
  carries the APL's spell rows while the APL's **pre-pull** rows live in a per-class pre-pull
  table (`ST.WARRIOR.PRACTICE_PREPULLS`, `ST.HUNTER.PRACTICE_PREPULLS`,
  `ST.ROGUE.practice_prepulls`, `ST.DRUID.PRACTICE_PREPULLS`,
  `ST.SHAMAN.PRACTICE_PREPULLS`, `ST.PALADIN.practice_prepull_rows`); and every row carries
  **two** flags — `live` (the row's read exists and the line can be evaluated) and `engine`
  (the frozen engine has an arm that can ask for it). A row with no read is never asked for;
  a row with no arm is never a button that can be the right answer
  (`bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 and §9; the per-class build and live
  artifacts).
- **Warrior.** Battle Stance (2457), Berserker Stance (2458), Gladiator Stance (412513),
  Bloodrage (2687), Battle Shout (Era/Forever 25289, TBC 2048), Recklessness (1719), Death
  Wish (Era/Forever 12328, TBC 12292), Sweeping Strikes (12723), Berserker Rage (18499),
  Blood Fury (20572), plus the WotLK rows Thunder Clap (47502), Shattering Throw (64382) and
  Heroic Throw (57755). Twelve of the utility spine's thirteen rows carry an engine arm;
  **Gladiator Stance is `engine = false`** — the SoD APL gates it on the T1 damage set
  bonus, and the client can answer the Forecast buff but not the set ownership. (The
  compiled order's `cleave` row has no arm either — no rule ever outputs it)
  (`bench/warrior_apl_utility_build_2026-10-20.md` §1;
  `bench/warrior_apl_utility_live_2026-10-20.md` §§1, 4;
  `bench/warrior_utility_residuals_2026-10-20.md` §1).
- **Hunter.** Rapid Fire (3045), the Serpent Sting upkeep (25295 / 49001), the aspects (Viper
  34074, Hawk 27044, Dragonhawk 61847, Falcon 469145), Kill Shot (the SoD rune 409593, WotLK
  61006), Silencing Shot (34490), Explosive Trap (49067), Multi-Shot (49048), Black Arrow
  (63672), Raptor Strike (14266), Hunter's Mark (14325), Mongoose Bite (14271), Immolation
  Trap (14305), Wing Clip (14268), Arcane Shot (14287) and Wyvern Strike (458482) — one row
  per family, each at the APL's own priority position
  (`bench/hunter_apl_utility_build_2026-10-20.md` §3;
  `bench/hunter_utility_live_2026-10-20.md` §1).
- **Rogue.** Vanish (SoD 1856, WotLK 26889, Forever 1857), Preparation (14185),
  Premeditation (14183), Ambush (11269), Garrote (11290), Venom (1310703), the SoD Poisoned
  Knife (425012), Tricks of the Trade (57934), Killing Spree (51690), Blood Fury (20572),
  Elune's Light (1259799) and the Gnome racial **Eureka!** (1259812). The **Cloak of Shadows
  row was refuted** — 1857 is Vanish rank 2 on the TBC and Forever clients and the spell does
  not exist on either (it was removed in 2.3)
  (`bench/rogue_apl_utility_build_2026-10-20.md` §1 and §3;
  `bench/rogue_apl_residual_reads_2026-10-20.md` §§1-2).
- **Druid.** Cat Form (768), Leader of the Pack (17007), Faerie Fire (Feral) (17392 / 27011),
  Innervate (29166), Elune's Light (1259799) and the TBC Bloodlust row (2825), with Claw
  (9850) left RESERVED (the read that decides "the Shred cannot land" does not exist) and
  the Bloodlust row honestly `live = false` — **2825 is the Shaman's Bloodlust**, a spell the
  druid cannot cast, and the APL's own "Bloodlust Time" variable has no addon counterpart
  (`bench/druid_apl_utility_build_2026-10-20.md` §3;
  `bench/druid_apl_residuals_2026-10-20.md` §§4-5).
- **Shaman.** Bloodlust (2825, WotLK), Strength of Earth (Era 10442 / TBC 25528 / Forever
  25361), Mana Spring (25570, TBC) and Frost Shock (25464, TBC), each at the APL's own
  position; the Lightning Shield maintain now covers SoD and Forever as well, and the Frost
  Shock filler is a real, class-owned option (`guide_filler_shock`, default `earth` — the
  APL's own default) instead of a dead variable
  (`bench/shaman_apl_utility_build_2026-10-20.md` §1;
  `bench/shaman_residuals_2026-10-20.md` §§1.1-1.2).
- **Paladin.** Every rotation row now carries its APL citation, its family gate, its
  per-family id and its TBC name. The rotation table carries **17** rows: the twelve shipped
  ones plus the APL utility layer's five — **Hand of Reckoning (67485)** and **Hammer of
  Wrath (48806)** (the WotLK APL's top two rows, both with an engine arm), plus
  **Judgement of Wisdom (53408)**, **Holy Strike (10333)** and **Divine Favor (20216)**,
  which are live (their read exists) but carry **no engine arm** and so never appear as a
  button. The guide carries **twelve** slots (the two band rows are new) and the pre-pull
  table carries **eleven** rows — TBC (Sanctity Aura 20218, Seal of Command 20375, Seal of
  the Crusader 27158, Judgement 20271, Seal of Blood 31892), Forever (Retribution Aura
  10301, Seal of Command 20920, Seal of the Crusader 20308) and SoD (Seal of Command
  20920, Seal of Martyrdom 407798) — with no pre-pull row ever in the combat rotation.
  The spell names are the table's own labels (`ST.PALADIN.practice_prepull_rows`): **20920
  is Seal of Command** (the class's own seal ladder puts it there, and the Forever
  client's own ladder agrees) and **20308 is Seal of the Crusader**. Divine Storm and
  Holy Shock are different spells in this tree — Divine Storm is 407778 (SoD) / 53385
  (WotLK) and Holy Shock is 20930 — and neither is a row of this table. One label is
  contested inside the tree: the class's own `sob` rotation row names the same SoD 20920
  r5 "Seal of Martyrdom" (that row's own SoD id is 407798), so the two spell names for
  that id disagree between the pre-pull table and a source comment — this entry follows
  the pre-pull table. The two WotLK band
  rows also ship as **HUD mirrors**: `hud_show_hor` and `hud_show_how_wrath`, both **off**
  by default and WotLK-only, and the paladin's three HUD templates now name all
  **fourteen** shipped slots (the band rides P-T2 "Full Ret + Trinkets" and stays off in
  P-T1/P-T3). A correction to the earlier release notes: the pre-pull table was recorded
  here as carrying two rows (Sanctity Aura on TBC, Retribution Aura 10301 on Forever) — it carries eleven
  (`bench/paladin_apl_utility_build_2026-10-20.md` §§2.1–2.5;
  `bench/paladin_hud_utility_band_2026-10-20.md` §§1.2–1.3;
  `bench/paladin_audit_close_2026-10-20.md` §§1.2–1.3).
- **The warrior's Heroic Strike / Cleave queue drill** (`warrior_hs_queue`) — the operator's
  mechanic, with the sim's own citation: the queue lifts the dual-wield miss penalty
  (`DisableDWMissPenalty`), and the penalty it lifts is **+19 % over a 5 % white base**. The
  drill grades the press **window** — the gap between the mainhand's last swing and the
  offhand's next swing — on the tighter of the two sides (S ≥ 250 ms, A ≥ 150 ms, B ≥ 80 ms,
  C ≥ 20 ms, D inside the window, F outside it). The sim's 250 ms is its own reaction-time
  model, **not** a client fact: the in-client window is UNCONFIRMED
  (`bench/warrior_hs_queue_2026-10-20.md` §§1-2). **Correction to the earlier release notes in
  this section:** the first documentation pass recorded this drill as absent from the build;
  it landed on 2026-10-20 and that note has been removed.
- **The corpus was corrected — do not trust the old ids.** The rotation-gap analysis is the
  seed of most of the wrong ids in the corpus, and the five utility lanes re-fetched every
  APL file and every sim spell table and **disproved 31 ids, names and gates**. The
  corrections are applied in place in `bench/rotation_gap_vs_apl_2026-10-20.md` (§0.0 lists
  each one with its old value, its corrected value and its evidence; §9 summarises them), and
  sixteen other bench files were corrected the same way. The headline ones: **17364 =
  Stormstrike** (no wowsims shaman sim has a Nature's Wrath ability at all), **1857 = Vanish
  rank 2** (not Cloak of Shadows), **9850 = Claw rank 5** on Era, TBC *and* Forever — and the
  **Forever client has no Mangle spell at all**, **2825 is the Shaman's Bloodlust**, the WotLK
  hunter's **Kill Shot is 61006** and its **Explosive Shot 60053** (53351 / 53301 are the
  client's rank-1 fallbacks), the TBC **Steady Shot is 34120** (56641 does not exist on the
  TBC client), and the **Forever client has no Steady Shot at all** — its row was removed
  (`bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 and §9).
- **The Forever druid chain no longer names a spell the client does not have.** The Mangle
  branch answered "mangle" on every tick on the Forever client (the spell does not exist
  there, so the Mangle timer is always nil), which made the Bite and the builder branches
  unreachable; the branch was removed and the chain now follows the APL's own order
  (`bench/druid_apl_residuals_2026-10-20.md` §1).
- **Offline state at this landing:** `bash tests/run.sh` → 41 steps, 0 failed; luacheck →
  2 warnings / 0 errors in 83 files (the standing floor; both warnings are pre-existing, in
  files this wave never touched). Every behaviour above is verified offline only — the
  in-client checklist in TESTING.md and the operator script in
  `bench/live_test_script_2026-10-19.md` are the owner acceptance pass.

### Audit-fix wave (2026-10-20, verified offline, UNCONFIRMED in-client)

The post-everything deep audit found two HIGH and four MEDIUM defects in the practice
surface, the paladin's rotation slice and the compat contract. All six are closed. Every
entry below is **verified offline, UNCONFIRMED in-client** — the operator's session is the
only thing that can confirm the in-client behaviour.

- **HIGH — the druid's press-nothing hold was graded as an action (the bear's queued
  Maul).** The druid was the only class of six that mapped the guide's HOLD onto a
  synthetic press: every hold text became an action key, so the guide's `RIDE` (the bear
  chain's queued Maul — the guide already said *no action*) turned into a "ride" button.
  Both directions were wrong: pressing **nothing** (correct) read as a miss → **F**, and
  pressing the rendered "ride" button graded **S with points** — points for idling, which
  the engine's hold contract forbids. The class's own priority drill also banked a false
  mis-pick for every real pick. The guide's hold vocabulary is now split in two, as two
  published tables: `ST.DRUID.PRACTICE_HOLD_KEYS` (the nine **spell-naming** holds → the
  action to press) and `ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING` (the one **press-nothing**
  hold, `RIDE`). The scenario step states the press-nothing hold as
  `{ action = nil, hold = true, reason = "RIDE" }` — a cast during it is an illegal cast
  (F), doing nothing during it is correct but worth no points — and the priority drill
  skips hold steps, so a hold banks no mis-pick
  (`bench/druid_hold_ride_2026-10-20.md` §§1–3).
- **HIGH — a completed practice session was lost on logout.** `ui.end_progress_session` was
  the only writer of the completion bonus, the daily streak (class and account), the run
  counter, the accumulated time active and the bounded history row — and it had exactly
  one caller: the session's stop. `PLAYER_LOGOUT` did not flush it, so a player who
  practised and then logged out kept the per-attempt XP and lost everything else, with no
  error and no notice. A dedicated `ui.flush_progress_session(self, now)` now ends and
  persists the progression session **without** tearing the frames down (a logout is not a
  session end), is idempotent, and reports honestly whether it wrote. It has three
  callers: the session's stop, `main.lua`'s `PLAYER_LOGOUT`, and the practice panel's
  hide. The write lands in the saved variables because AceDB registers its own
  `PLAYER_LOGOUT` handler at library load — before this one — so it has already stripped
  the defaults when the addon writes the fresh blob into `profile.practice`
  (`bench/practice_persist_2026-10-20.md` §"H2").
  **The caveat is stated, not hidden:** a UI `/reload` fires **no** `PLAYER_LOGOUT` and
  writes **no** SavedVariables — the client serialises them at logout only — so a
  mid-session reload loses the in-flight session whatever the addon does. That is client
  behaviour, not an addon defect (`bench/practice_persist_2026-10-20.md` §"H2", caveat).
- **MEDIUM — a Progress-page reset mid-session dropped every later attempt.** The reset
  nils the hook lane's live cache, and the attempt recorder then returned before the
  profile was re-created — so the score kept moving while no XP, mastery, streak, stats or
  badge did, with no error. Two halves: the attempt recorder now ensures the profile
  itself before it records, and the reset also clears the **in-flight session's** counters
  (the session keeps running; only the progression bookkeeping restarts, and the erased XP
  comes off the badge). The session's start stamp is deliberately **not** reset, so the
  run's time active still matches the score summary the history row carries
  (`bench/practice_persist_2026-10-20.md` §"M1").
- **MEDIUM — the paladin's practice rotation slice ignored the family gate.** The slice
  offered the TBC client a "Hammer of Wrath" button the TBC rotation can **never** ask
  for — the `how` row declares `ERA`/`SOD`/`FOREVER`, and the engine's execute arm is
  Era/Forever only — so pressing it graded `out_of_order` → **F** for a spell the
  rotation never wanted. The slice now applies the same `families` predicate the rogue,
  warrior and druid slices use, on **both** paths (the order's own keys and the APL-row
  path). The family token comes from the **order**, not the client: the SoD game runs on
  the Era client, so the SoD variants' own orders name `SOD`. The per-client slices after
  the gate: **TBC** drops `how`; **Era** drops `cons`/`exo` from the rotation part of the
  strip (the corpus's family gate — the Era APL carries no filler row) while the presses
  stay reachable through the panel's asked-for vocabulary; **Forever** drops `cs`/`sob`;
  **SoD** and **WotLK** are unchanged (`bench/paladin_audit_close_2026-10-20.md` §1.1).
- **MEDIUM — the spell-knowledge contract did not match the code.** `compat.lua`'s comment
  claimed a client with none of the probes reports `"unknown"` instead of erroring; the
  code answered `false`. Every current caller treats `false` as fail-closed, so the
  behaviour was safe, but the contract was wrong: a caller could not tell "no probe
  answered on this client" from "the player does not know the spell", and a row that must
  hide when the client cannot answer had no way through the API. The boolean stays
  **binary, never nil** (a `nil` answer was proven *not* behaviour-neutral for two raw
  consumers), the comment now states the contract the code implements, and an **additive**
  `api.is_spell_known_state(spell_id)` answers the tri-state
  `true,"known"` / `false,"not_known"` / `false,"unknown"`. No existing caller was touched,
  and the paladin's WotLK HUD band gate now reads that state, so "the player does not know
  it" is distinguishable from "this client cannot answer" (both still hide — unknown
  hides). `api.is_spell_known` itself is unchanged
  (`bench/compat_m3_contract_2026-10-20.md` §§1–3;
  `bench/paladin_audit_close_2026-10-20.md` §1.5).
- **MEDIUM — a client without a calendar froze the daily XP cap forever.** `current_day()`
  returned `nil` when the client has no `date`, and the pure layer resets the drill's daily
  cap only when the day ordinal is non-nil and the day changed — so the counter
  accumulated across days until the drill awarded **0 XP for good**, silently. Two layers:
  the day falls back to the client's own **clock** (`floor(time()/86400)` — an opaque day
  counter whose consecutive days differ by exactly 1), so the cap still resets every day
  and the daily streak still advances; and a client with neither a calendar nor a clock
  now prints **one** notice naming the cause instead of silently awarding nothing. The
  notice goes through the addon's own printer, not the badge-gated announcer, because a
  diagnostic that rides an opt-in toggle is a diagnostic nobody sees
  (`bench/practice_persist_2026-10-20.md` §"M4").
- **Dated history note (2026-10-20).** The "Scenario surface + APL utility layer" entry
  above originally recorded the druid as stating **no hold at all**; that wording was
  corrected in place when the HIGH defect above was fixed, so no correction is owed to it
  now. The druid's guide holds in two shapes — nine spell-naming holds (a decision to
  *cast*) and one press-nothing hold (`RIDE`, the bear chain's queued Maul) — split by
  `ST.DRUID.PRACTICE_HOLD_KEYS` and `ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING`
  (`bench/druid_hold_ride_2026-10-20.md` §7; `bench/class_hold_statements_2026-10-20.md`
  §2, whose druid row is superseded by that file).
- **Offline state at this landing:** `bash tests/run.sh` → 41 steps, 0 failed; luacheck →
  2 warnings / 0 errors in 83 files (the standing floor; both warnings are pre-existing, in
  files this wave never touched). Every behaviour above is verified offline only.

### Neutral actions, family scope, HUD ids, progression and contracts (2026-10-20, verified offline, UNCONFIRMED in-client)

- **The NEUTRAL action — the engine half.** A class publishes the action keys that are
  legitimate but never asked for, and the engine stops grading them as mistakes. The
  publish is `ST.<CLASS>.practice_neutral_actions` — flat, or one bucket per family (the
  bucket for the running `st.family`; a family the class published no bucket for answers
  nil, never a guess), read through one accessor, `H.practice_neutral_actions(class_key)`
  (nil-safe, nil for an unknown class, and it hands out a copy of the published set).
  `H.rotation_run_decide` gained a **neutral** outcome: the press records **no attempt**
  — no points, no streak, no mastery tick, no XP — and it is **not** a mis-pick. The panel
  shows `NEUTRAL` in the popup and the status line, and the run summary reports the
  neutral count only when it is above zero, so a class with no published set reads exactly
  as before. A HOLD still beats the neutral set (a cast during an explicit hold stays an
  illegal cast, F) and the rotation action beats it too (the expected action is graded
  first, so a rotation press still hits). The neutral outcome lives in the **rotation
  scenario**; a drill-list press is graded by the class's own drill grader and is not
  neutral there (`bench/practice_neutral_actions_2026-10-20.md`).
- **The per-class sets.** All six classes publish one today: the **paladin**
  (family-scoped — `sotc`, `aw`, `hpot`, `abacus`, `stop`, plus the common abilities
  `holy_light`, `flash_of_light`, `lay_on_hands`, `divine_shield`, `bop`, `food` on
  Era, TBC, WotLK and Forever, and the same ten keys WITHOUT `sotc` on Cata, Mists and
  Retail — the Seal of the Crusader went away in 4.0, so the class publishes it on the
  classic line only and a press of that key on the 4.0+ clients is a mis-pick, the
  rogue's Shiv treatment on the same clients), the
  **warrior** (family-scoped — `sprint`, `demoralizing_shout`, `healthstone`, `flask`,
  `food` on every family, `battle_shout` on WotLK, `cleave` on Forever), the **rogue**
  (family-scoped — `sprint`, `evasion`, `kick`, `healthstone`, `food` on every family,
  `coldblood` on Era and WotLK, `shiv` on WotLK and Forever) and the **shaman** (flat —
  `healing_wave`, `chain_heal`, `water_shield`, `healing_potion`, `food`). The **hunter**
  and the **druid** publish family-scoped buckets as well — Era, TBC, WotLK and Forever
  for both, the hunter's without `raptor` on WotLK and Forever and the druid's without
  `rake` on WotLK and Forever. The four classes that publish **no bucket for
  Cata, Mists or Retail** — the warrior, the rogue, the hunter and the druid — offer
  **no** common ability at all there (the paladin and the shaman still answer every
  family: the paladin with its ten-key 4.0+ bucket, the shaman with its flat set)
  (`bench/class_neutral_family_coverage_2026-10-20.md` §1.2/§5;
  `bench/final_gate_fixes_2026-10-20.md` §2). The
  common abilities needed a key first, so each of the six classes publishes a
  **practice-panel ability list** (`ST.<CLASS>.practice_common_actions` — the English
  spell name first, the cited id ladder second, family-correct: the name on TBC, the
  numeric id elsewhere) and appends it to the class's own guide slot list inside the
  practice block of `post_init`, after the guide frame built its icons — so the live
  next-action guide is untouched while the practice panel's action row offers them with
  their own icons. An ability the running client does not have is dropped
  (unknown-hides): the panel never offers a button the client cannot cast. A rotation
  action may never be published as neutral, and the panel vocabulary stays a closed list
  — every key is classified rotation / neutral / intentional mis-pick
  (`bench/class_neutral_actions_2026-10-20.md`;
  `bench/class_common_actions_2026-10-20.md`).
- **The shaman's practice surface is family-scoped now.** The rotation table's per-row
  `families` list was read by nothing at runtime and there was no accessor, so the panel
  fell back to the guide-slot vocabulary and offered **every** row on **every** client —
  a TBC client was offered the WotLK-only Call of the Elements and Bloodlust rows and
  the Era-only Molten Blast, Lava Lash, Chain Lightning, Windfury Totem and Grace of Air
  rows, so pressing one could only ever grade wrong.
  `ST.SHAMAN.practice_rotation_for(family)` now answers the family's rows in the table's
  own order; the argument-free call answers the client's family **plus** the running
  build's token, so the SoD build's own row rides the Era slice, and an unknown family
  answers an empty slice. `ST.SHAMAN.family_guide_slots` cuts the guide's slot set from
  the same `families` list, and `ST.SHAMAN.apply_family_slots()` narrows the published
  `guide.slots` to the running family's set (called from `post_init` after the guide
  frame and the HUD are built, and again when the SoD build becomes known). The
  per-family slices: **Era 13 rows, TBC 13, WotLK 13, Forever 7**, and the SoD build's
  own slice **14** (the Era slice plus its Lightning Shield row).
  `ST.SHAMAN.PRACTICE_PREPULLS` has no consumer — the class ships no pre-pull drill —
  and the class file now says so (`bench/shaman_family_scope_2026-10-20.md`).
- **The hunter's HUD slots carry the running family's own rank.** One owner for both
  surfaces: `SPELL_ID_BY_FAMILY` — the HUD slot and the guide slot of a key read the
  same entry, so the two can never disagree about which spell the running client has; a
  family with no entry for a key cannot have that spell, and the HUD's dead-slot filter
  drops the slot while the guide's slot set does not declare it (the Steady Shot keeps
  its own owner). The runtime re-point now re-points **every** spell slot with the
  client's own rank, not only the Steady and the Aimed ones. The per-family HUD slot
  counts: **Era base 6, Era/SoD 7, TBC 9, WotLK 9, Forever 7, Cata 9, Mists 8, Retail 9**
  — the **Forever row is seven slots**, because the Forever client has neither a Steady
  Shot nor a Kill Command and both slots are dropped (`bench/hunter_hud_family_2026-10-20.md`).
- **The progression surface, six fixes.** (1) **The daily-cap floor** — the cap is
  `max(3 x the median of the drill's HIT points, its best hit in the window)`, taken over
  hits only, so a miss (which earns nothing) no longer drags the cap down; without the
  floor a drill below 50% accuracy had a cap of **0** and swallowed every award for good.
  (2) **The cap notice** — the swallow is now reported: "Practice XP: this drill has
  reached today's XP cap (3x its median hit XP); it earns again after the next day.",
  once per drill per day, through the addon's own printer and not the badge-gated
  announcer, so a progression dead end is never silent. (3) **The account scope** — the
  session end evaluates the class scope **and** the account scope
  (`P.evaluate_unlocks_both`), so an account-scoped achievement can fire at all; the
  unlock flags live in the scope they were earned in. (4) **The streak readout** — the
  stats summary and the stats frame's summary line now carry the **daily streak** next to
  the lifetime best ("Best streak %d  |  Daily streak %d"); it was computed and never
  displayed. (5) **The reset-arm expiry** — the two-step reset's armed state now expires
  after 15 seconds, checked lazily at every decision point, so a stale "Confirm: reset
  all practice progress" can never wipe the profile minutes later. (6) **The NO_DAY
  sentinel** — the history day is read signed, so the "no date recorded" marker (-1)
  survives the repair and the export and renders as "-" instead of 1970-01-01, while a
  day of 0 (the epoch) stays 0. Alongside them: a saved blob a newer build owns is
  protected **and** reported ("this session's XP is not being saved"), and the logout
  flush reports the **write**, not the close (`bench/progression_fixes_2026-10-20.md`;
  `bench/progression_ui_fixes_2026-10-20.md`).
- **The drill-list press is the pick.** The press is written into every alias the class
  graders read (`ctx.pick`, `ctx.pressed`, `ctx.action`), so a class that publishes its
  own pick alias can no longer shadow the player's press. The block used to fill only an
  *empty* alias, and the hunter publishes `ctx.pick` (the live cast) and reads it first —
  a drill-list press made while a Steady Shot was casting was graded against the live
  cast instead of the press (measured: grade F for a correct press). A class's own pick
  still survives a **press-less** drill press (the hunter's shot drills judge the shot in
  flight), and the scenario path — a different call site — keeps the live cast as the
  pick. The contract is pinned against the six classes' **real** graders: each class is
  driven end to end through the drill-list path (the action press and the drill press),
  each answers a letter, and the pick the rotation wanted grades S; the negative half (no
  pick -> nil) is what makes the positive half mean something
  (`bench/drill_pick_contract_2026-10-20.md`).
- **The pre-pull contract suite.** NEW `tests/prepull_contract_state.lua` proves the
  contract between a class's pre-pull drill and that class's own pre-pull table over the
  eight published tables of the six classes: each is proved **GRADED** (the hunter's and
  the warrior's, with their late-band tables, and the rogue's) or **CITATION-only** (the
  druid's, the shaman's and the paladin's rows table) — a citation table has **no reader
  anywhere in the addon tree** and the comment above its declaration carries the marker,
  and a drill reads **its own** table and no other class's (coupling and cross-isolation).
  The paladin is the one class with both shapes: `paladin_prepull` grades the class's own
  per-order **seal spec**, and `ST.PALADIN.practice_prepull_rows` is the marked citation
  layer. The paladin's flags are now strict booleans on every row plus the
  needs-when-unread rule over both axes, and the druid's table gained the "no consumer —
  citations only" marker (`bench/prepull_contract_2026-10-20.md`).
- **The documentation-truth corrections.** A sibling lane re-audited `README.md`,
  `TESTING.md` and the operator's live script against the tree and corrected them:
  **`/st diag verbose` does not exist** — the handler matches only the empty argument,
  `practice`, `design` and `diag`, and `/st diag` **is** the verbose report; the rogue's
  Slice and Dice upkeep is **armed**, so the script no longer asks the operator to confirm
  its absence, and the rogue's Forever pre-pull is **Blade Flurry 13877 @-2** with the
  builder chain `{Saber Slash, Mutilate, Hemorrhage}`; the **Cata (40402)** and **Mists
  (50500)** flavours are listed and explained (those two ship without the swing-engine
  library, so the bars are inert); the expected `/st diag` shape carries the **ticks**
  line; the paladin's utility layer is recorded as landed; and the usable-only trinket
  gate and the warrior's W-21 HUD mirrors got their operator steps. This changelog was
  audited in the same pass and is corrected here: the paladin pre-pull names, the
  warrior's drill count, the design-target count, the void correction notice and the two
  copy strings (`desks/docstruth-audit/journal.md`).
- **Offline state at this landing:** `bash tests/run.sh` → 43 steps, 0 failed; luacheck →
  2 warnings / 0 errors in 85 files (the standing floor; both warnings are pre-existing, in
  `compat.lua` and `main.lua`, files this wave never touched). Every behaviour above is
  verified offline only — the in-client checklist in `TESTING.md` and the operator script
  in `bench/live_test_script_2026-10-19.md` are the owner acceptance pass.

### Operator test-session wave (2026-10-21, verified offline, UNCONFIRMED in-client)

Found by the operator's first in-client session on Classic Era 1.15.9; the range fix and the
design-mode work are verified offline, the in-client confirmation is still owed.

- **Fixed — the range poll no longer calls a client-BLOCKED API.** On Classic Era the addon
  raised `[ADDON_ACTION_BLOCKED] AddOn 'SwedgeTimer' tried to call the protected function`
  from the vendored `LibRangeCheck-2.0` item-range checker (`LibRangeCheck-2.0.lua:498`,
  reached from `main.lua:1797`): the library resolves `IsItemInRange` to
  `C_Item.IsItemInRange` on every modern client (on the classic branches the legacy global
  *is* that function — `Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:29`), whose
  call the client blocks for addon code and whose argument shape is an `ItemInfo`, not the
  legacy item id. The library now builds **no item checkers and no spell checkers** on any
  shipped family, so the melee/ranged ladder is one uniform thing everywhere — the
  interact-distance bands: melee 8 yd, ranged 28 yd (Tauren 6/25, Scourge 7/27) — and it
  calls **zero** client range APIs on Classic Era, TBC Anniversary, WotLK Titanforge, Retail
  and WoW Forever. The old per-family divergence (the legacy spell-range global exists in
  some client binaries and not in others) can no longer change the behaviour.
  **Accepted coarsening, stated plainly:** the range band is the client's interact-distance
  band, not the class's spell range, so the bar's range readout reads a band instead of the
  class's own reach. The accurate per-class range (the modern `C_Spell` path) is an open
  follow-up that needs one in-client confirmation; it is deliberately not shipped on a
  guess.
- **Changed — design mode no longer fights the options panel.** The design chrome now draws
  *above* the AceConfig options panel (strata `FULLSCREEN_DIALOG`, levels 110-150) instead of
  behind it, every full-screen design frame is explicitly mouse-transparent, and the
  per-element drag inputs sit *below* the panel, so the panel's title-bar drag can never be
  swallowed by design mode. Esc no longer ends the session while an options window is open,
  and closing the options panel leaves design mode active — you can now close the panel and
  keep designing.
- **Added — a design control panel.** While design mode is on, a small movable panel (no db
  key; a session state like design mode itself) offers **Lock frames / Unlock frames** (the
  overlays stay visible but frozen: no drags, no double-click reset) and **Exit**.
- **Added — `tools/deploy.sh`.** Copies the exact shipped file set to a client folder and
  verifies byte parity. The six `Error loading SwedgeTimer/classes/*.lua` warnings of this
  session were a hand copy that never carried the `classes/` subdirectory — the files were in
  the repo and the TOC listed them, the deployed folder simply did not have them.
- **Offline state at this landing:** `bash tests/run.sh` → 43 steps, 0 failed; luacheck →
  2 warnings / 0 errors in 85 files (the standing floor). `tests/lrc_guard_state.lua` →
  170 checks; `tests/designmode_state.lua` → 655 checks. The new behaviour is verified
  offline only; in-client confirmation on Classic Era is owed for the range error, the
  design-mode layering and the new control panel.

## [2.0.8] -- 2023-05-09

### Added

- Swing timers can now be enabled or disabled depending on which Dual-Specialization group the player is using.
- Further to the above, Warriors now have the option to disable the swing timer when in Arms or Protection spec.

### Fixed

- Fixed a bug where indeterminate ordering of event callbacks was makinng the weapon checks for offhand and ranged lag behind
  equipment changes. This will fix a bug for warriors where ElvUI being loaded causes equipping a shield to break the offhand timer.
- Fixed an issue where an outdated version of LibCustomGlow was being used (if any other addon loaded by the user included the
  more up to date version of this library, the bug would not have occurred).

## [2.0.7] -- 2023-01-19

### Changed

- The addon has been confirmed to function properly in 3.4.1 and the Interface tag updated to reflect this.

## [2.0.6] - 2022-12-25

### Fixed

- The LibRangeCheck-2.0 library takes a finite amount of time on first client load to gather the information it needs to
  function properly. Previously, the code to show and hide bars was blocked until the range checking
  was functional. Now show/hide checks will be run immediately.
- Added some additional cross-checks to ensure bars show and hide when necessary.

## [2.0.5] - 2022-12-24

### Fixed

- Fixed an issue with warrior shields where the offhand timer bar initialisation was
  being broken by a zero attack speed. This might fix a bug warriors have experiencing
  with the offhand timer bar breaking during swaps, but still unclear.
- Timer bar elements are now properly recalculated in full when the player's weapon changes.

## [2.0.4] - 2022-11-24

### Added

- Seal of Justice custom timer bar color added for Paladins.
- Druids can now enable custom bar visibilities based on their current form.
- Druids can now enable custom bar colours for travel and flight form.

### Fixed

- Druid forms now properly respect the adaptive form index for Moonkin and Tree form
depending on if Moonkin and Tree forms are currently talented.

## [2.0.3] - 2022-11-15

### Fixed

- Addon now uses an updated version of LibClassicSwingTimerAPI, which fixes some lua errors around C_Timers.

## [2.0.2] - 2022-10-11

### Added

- Warrior Bloodsurge glow proc options added
- Bar Positioning menus now also lets the user change bar dimensions there

### Fixed

- Typo in GCD marker settings fixed

## [2.0.1] - 2202-10-08

### Fixed

- Removed an eroneous debug print when druids cast Maul.
- Fixed typo in the settings UI's info panel.

## [2.0.0] - 2022-10-07

The TBC Ret Paladin version of the Addon has been re-written from the ground up to support
every class in WotLK.

### Added

- Support for mainhand/offhand/ranged swing timers.
- Ships tailored and customisable timer configurations for every class in WotLK.
- Some classes (Druid/Hunter/Paladin/Warrior) ship with specific aura/proc monitors that are
  configurable in the settings menu.
- Support for adjustable scale with the mousewheel when the timers are not locked.
- A range finder is now included that can dim the timer when the player is out of range.
  The range estimation is now an option for timer texts, with a new central text option to support it.
- GCD markers now support showing the physical or spell GCD duration, and can be anchored to both
  the end of the swing timer bar, or to the progress bar itself, moving with the timer progress.

### Changed

- SwedgeTimer no longer implements its own Swing Timer engine, it now uses LibClassicSwingTimerAPI, a project by Ralgathor (with contributions from Swedge and Buds) that produces a standardised swing timer API. It takes account of the many different edge cases the WoW swing timer has for each class.
- Timer border and background customisation has been improved.
- Improved timer positioning within the UI powered by LibWindow-1.1.

### Removed

- With the demise of Seal Twisting, some of the Ret Paladin functionality to help with seal
  twisting has been removed. Much of that functionality is generally useful, and has been adapted into the rest of the addon.
