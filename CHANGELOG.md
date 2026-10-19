# Changelog

## [Unreleased]

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
  contract (each with a pure decision engine and an offline suite). The four new guides ship
  disabled until verified in client; the paladin guide is unchanged.
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
  ships with its toggle only — the multi-target engine is a future round;
  `hunter_multi_target` copy marked "(future)".
- Enterprise-grade wave: options-file warnings wired, practice panel/timeline/
  scoring fixes, HUD provider-hidden slots now hide (no stale live-looking
  icons) with hidden-slot row reflow deferred past combat lockdown, practice
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