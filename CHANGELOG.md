# Changelog

## [2.2.1]

**Verification status:** offline gate only — `bash tests/run.sh` **59 steps / 0 failed**; `luacheck .` **5 warnings / 0 errors in 105 files**. In-client behaviour on WoW Forever and Classic clients is **UNCONFIRMED**; no in-client pass is recorded for 2.2.1.

### Changed

- **Version 2.2.1:** `SwedgeTimer.toc` and `main.lua` report version `2.2.1`.
- **Offhand bar off by default (`config_presets.lua`):** `offhand.enabled` now defaults to `false` for all dual-wield/ranged classes (`DEATHKNIGHT`, `HUNTER`, `ROGUE`, `SHAMAN`, `WARRIOR`; `DRUID` already defaulted to `false`). As a result, `power_bar.lua` anchors under the `mainhand` bar by default and automatically moves under `offhand` when the offhand bar is enabled (and an offhand weapon is equipped).
- **Bar anchor cleanup (`bars.lua`):** removed the redundant `anchor_frame:SetPoint("CENTER")` call immediately preceding `LWIN.RestorePosition(anchor_frame)` in `configure_bar_size_and_positions`.

### Performance

- **Stateless `iter_hands()` (`main.lua`):** replaced the per-call closure allocation in `ST:iter_hands()` with a cached stateless iterator, eliminating ~40 closure allocations/sec from the 20 Hz range/visibility heartbeat.
- **Throttled driver fast-paths (`hud.lua`, `rotationtext.lua`, `nextaction_ui.lua`):** `HUD.on_update` and `RT.on_update` now check their `TICK` accumulator before calling `get_class_table()`, and `nextaction_ui.update` uses the `OnUpdate` `elapsed` argument between compute intervals instead of calling `api.get_time()` on every frame.
- **Reduced redundant frame widget calls (`bars.lua`, `main.lua`):** `ST:handle_oor_hand` caches `_last_alpha` per hand before calling `SetAlpha`, `onupdate_common` caches `_spark_shown` before calling `spark:Show()`/`Hide()`, and `set_bar_texts` caches `_st_shown` per font string before calling `Show()`/`Hide()`.

### Fixed

- **WoW Forever swing speed secret-safety (`swing_source.lua`):**
  - `read_equipped_speed("ranged")` now falls back to `UnitRangedDamage("player")` when `UnitAttackSpeed("player")` returns a restricted (secret) or non-accessible ranged speed, instead of gating the fallback behind `canaccessvalue(speed)`.
  - `on_unit_attack_speed` and `on_weapon_slot_changed` now check `is_secret`/`canaccessvalue` per active hand instead of aborting all hands if an unused hand's speed is secret.

## [2.2.0]

**Verification status:** offline gate only — `bash tests/run.sh` **59 steps / 0 failed**; `luacheck .` **4 warnings / 0 errors in 105 files**. In-client behaviour on the Forever client is **UNCONFIRMED**; no in-client pass is recorded for 2.2.0.

### Fixed

- **Queued-shot and queued-Maul detection (`classes/hunter.lua`, `classes/druid.lua`):** `api.IsCurrentSpell` is the client **predicate** (`C_Spell.IsCurrentSpell(spellIdentifier)`), not a getter. Raptor Strike / Steady Shot / Maul detection now passes each queue token (`api.IsCurrentSpell(token)`) instead of calling it with no argument; the no-argument form throws `bad argument #1 to 'IsCurrentSpell'` on Forever when a macro queues the shot (21 in-client errors), and returned nothing on the other clients. The test sandboxes now raise on a nil token, so the bad-argument contract is pinned.
- **Druid rage-cost probe (`classes/druid.lua`):** the cost read is guarded by `spell_id` before `pcall(api.GetSpellPowerCost, spell_id)`; an unresolvable/absent rank no longer issues a nil spell query (the prior nil-safe rewrite made one probe per unresolved rank, failing the F4 no-query contract).

### Changed

- **Version 2.2.0:** `SwedgeTimer.toc` and `main.lua` report version `2.2.0` (the TOC remains the single load order for every client).
- **Bar tick clock (`bars.lua`):** the tick reads the live client clock (`st.api.get_time()`) exactly once per tick. Accumulating the `OnUpdate` delta into a cached clock was removed: a bar's `OnUpdate` pauses while its frame is hidden and across loading screens, so the cached reading resumes stale and the fill sits at zero until it replays the hidden gap (the "bars display but never function" symptom). The single live reading is shared by the flash fade, the text timers and every paint path; the no-cycle early-return paint reuses it. The fill-last and 2026-10-28 resize-repaint guarantees are unchanged.
- **Aura icon rows (`aura_icons.lua`, `option_tables.lua`, `config_presets.lua`):** the buff and debuff rows now have separate width and height. Shipped default is **27 px wide × 20 px high** (previously a square 27 × 27; the 2026-11-09 width raise is kept). The native group layout pushes `elementWidth`/`elementHeight`, newly created and already-pooled buttons use `SetSize(width, height)`, and the reserved debuff band is computed from the icon **height** (so a width-only change no longer moves the rows). Options expose "Icon width" (`aura_icons_size`, 12–48) and "Icon height" (`aura_icons_height`, 12–48).
- **OnUpdate call contract (`main.lua`):** the installed frame script now adapts the client's `(frame, elapsed)` calling convention to the hand handler's single `elapsed` argument (`function(_, elapsed) onupdate(elapsed) end`). The previous direct install passed the frame as `elapsed`, which threw `attempt to perform arithmetic on a table value` at `bars.lua:1145` on the first warm tick in game. The diag counter wrapper keeps its one-argument contract and is adapted at the same boundary.
- **Vendored swing library (`Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua`):** every attack-speed/timer read is now probed with `canaccessvalue` before arithmetic or `C_Timer` scheduling, so a restricted speed read leaves the cycle on its scheduled stop instead of throwing. This is a local patch to a vendored file; see the 2.2.0 audit note about keeping `Libs/` upstream-clean.
- **Compat (`compat.lua`):** `api.UnitAttackSpeed` now returns only the main-hand and off-hand speeds (the ranged speed had no consumer; `swing_source.lua` keeps reading the raw client triple).

### Hardening

- **Secret-value access probes:** `compat.lua`, `hunter_ui.lua`, `enemy_swing.lua`, `forever_guide.lua`, `swing_source.lua`, `LibGlobalCooldown.lua` and the vendored swing library call `canaccessvalue`/`canaccessallvalues` before comparing, formatting or doing arithmetic on client reads (cooldown start/duration, cast start/end, attack speeds, target name/GUID, the cast-bar key).
- **Nil-safe guards:** broad nil/type guards across `aura_icons.lua`, `bars.lua`, `designmode.lua`, `diag.lua`, `main.lua`, `option_tables.lua`, `power_bar.lua`, `practice.lua`, `practice_progress.lua`, `practice_progress_ui.lua`, `practice_ui.lua`, `rogue_guide.lua`, `weave_range.lua` and `widgets.lua` so a missing profile row, table or client answer returns early instead of throwing.
- **Aura rows (`aura_icons.lua`):** row construction tolerates a missing row/state/list and no longer sets an explicit frame strata on the native container at creation; the client default applies.
- **Design-mode reset (`designmode.lua`):** the bar reset seam targets the class defaults row (the same source `hand_default` reads) and hands the live row to `LibWindow.RestorePosition`.
- **Options (`option_tables.lua`):** hand option generation returns early for an unknown hand row, and order offsets tolerate a nil offset.

### Tests

- **27 suites refreshed for the new contracts:** every sandbox that loads `compat.lua`/`swing_source.lua`/`forever_guide.lua` now provides the client's `canaccessvalue`/`canaccessallvalues` probes (secret-aware where the suite models restricted values), the strict `forever_guide.lua` allow-list includes `tonumber` and both probes, the `bars.lua` tick drives the handler's declared single-`elapsed` contract and pins the cold/warm cached-clock reads, the `aura_icons.lua` strata expectation follows the removed explicit set, the `designmode.lua` reset checks follow the class-defaults-row target, and the `main.lua` `timers_locked` source pin follows the current `(db_class or {})` read.

## [2.1.9]

### Fixed

- **WoW Forever Hunter Cast Bar & Aura Icon Clearance (`aura_icons.lua`, `hunter_ui.lua`):**
  - `topmost_hunter_widget` now resolves `st.hunter_ui` (the live addon table) in addition to `ST.hunter_ui`, and `hunter_ui.update` immediately invokes `st.aura_icons.anchor(self, false)` so cast bar / Rapid Fire / target-warning visibility changes re-anchor on the same frame without waiting for the 0.15 s poll.
  - `A.HUNTER_RANGED_GAP` is raised from `15` to `29` px (`17` px Auto Shot cast bar + `6` px `BAR_GAP` + `6` px `HUNTER_GAP`), keeping the `27` px debuff icons and their `5` px duration bars `7` px clear above the `Auto Shot` cast bar without overlapping or jumping between shots.
- **WoW Forever Buff & Cooldown Proc Icons Above Debuffs (`aura_icons.lua`, `main.lua`):**
  - Native `AuraContainer` frames are pre-anchored before `SetUnit`/`AddAuraGroup` so `self:IsVisible()` is true when `ShouldRegisterForDynamicEvents()` registers `UNIT_AURA`, and `SetAuraProcessingPolicy(0)` + `UpdateAllAuras()` are invoked after enabling/showing and on `ST:UNIT_TARGET` (`player`) target switches.
  - Added missing multi-rank buff/proc/cooldown/trinket/racial spell IDs across all 6 classes (`Rapid Killing` `35098`/`35099`, `The Beast Within` `34471`, `Deterrence` `19263`, `Furious Howl` `24604`/`24597`/`24603`/`24605`, `Expose Weakness` `34501`, `Master Tactician` `34839`, Warrior/Shaman `Flurry` ranks, `Enrage` ranks, `Bloodrage` `29131`, Paladin `Vengeance` ranks, `Reckoning` `20178`, `Blessing of Freedom` `1044`, `Divine Favor` `20216`, Shaman `Elemental Devastation` ranks / `Elemental Mastery` / `Clearcasting`, Druid `Tiger's Fury` / `Frenzied Regeneration` / `Nature's Grasp` ranks, Rogue `Evasion` R2 / `Remorseless Attacks`, Troll `Berserking` melee `20554` & ranged `26635`, Orc `Blood Fury` variants, and shared weapon/trinket procs).
- **WoW Forever Horizontal Distance Range Bar (`weave_range.lua`, `hunter_ui.lua`, `compat.lua`):**
  - Fixed `hunter_ui.spell_range_band()` and `weave_range.spell_band()` checking `== true` / `== false` against `compat.IsSpellInRange`, which normalizes `C_Spell.IsSpellInRange` to numeric `1` / `0`. Both now accept `1`/`true` and `0`/`false`, and fallback probes include numeric spell IDs (`2974`, `2973`, `75`).
  - `weave_range.init` arms `C_SwingTimer.EnableRangeCheck` for `mainhand` and `ranged`, `compat.lua` `position_distance` adds a Forever-gated `ClosestUnitPosition(UnitCreatureID(unit))` fallback when `UnitPosition` is unavailable, and all `weave_range` layout/anchor geometry and distance reads are guarded against secret values.
- **Visual Polish (`aura_icons.lua`, `weave_range.lua`):**
  - Added outlined fonts (`OUTLINE`) with drop shadows, gold stack counters, a secret-safe `<4.0s` red `C_CurveUtil.CreateColorCurve` duration text binding, reverse `CooldownFrameTemplate` radial sweeps on buff icons (`SetDurationCooldown`), dark-backed crimson debuff duration bars, and outlined text on the horizontal distance bar.

## [2.1.8]

**Verification status:** all WoW Forever changes in this release are verified offline only (red-first pins and mutation proofs; the final offline gate is green — `tests/run.sh` 58 steps / 0 failed, `luacheck` 2 warnings / 0 errors in 103 files, the standing floor). In-client behaviour on the Forever client — the real secret triggers and rendering, `StatusBar`/`SetAlphaFromBoolean` acceptance of restricted values, and the new `/st diag` counters and receipts — is UNCONFIRMED; no in-client pass is recorded for 2.1.8, and nothing here is a "verified in game" claim.

### Fixed

- **WoW Forever Auto Shot Display (`main.lua`):**
  - The visibility heartbeat no longer dies with the range poll: the show/hide and out-of-range passes run in their own `pcall`s, the re-arm is unconditional (a transient range-probe failure keeps its backoff and the previous paint while the heartbeat still re-arms), and every path — including the terminal range-check disable — still runs the visibility pass, so bars keep showing and hiding instead of freezing for the session.
  - A Forever ranged `SWING_TIMER_START`/`UPDATE`, a completed-shot receipt and a hunter `START`/`STOP_AUTOREPEAT_SPELL` each open the ranged bar in the same event instead of waiting for the next 0.05 s visibility poll.
  - A restricted weapon-stat read no longer flips `has_weapon` false: `check_weapons` moves a hand only on a readable number (a genuine unequip still answers 0), re-probes at world entry, and a Forever ranged/offhand `SWING_TIMER_START` proves that hand has a weapon and lazily builds its bar — closing the persistent "Auto Shot not displayed" variant.
  - Auto Shot auto-repeat is probed with the client's numeric spell id `75` instead of a localized name token, forced from the cooldown path and the autofire events, and throttled to 4/s from the class tick as a missed-event backstop; a change opens or closes the bar in that event.
- **WoW Forever Swing Payload Recovery (`swing_source.lua`):** a secret/malformed `PLAYER_SWING` duration on a known hand is recovered from the equipped weapon speed (`UnitAttackSpeed` per hand, `UnitRangedDamage` for ranged; every read `pcall`'d and secret-checked) instead of silently dropping one cycle; only "no readable speed" is a counted reject. Secret values are probed before any comparison, so a restricted payload cannot throw before a counter, and the first reject prints a once-per-session notice (`speed_fallbacks` and `first_reject_notice` are in `/st diag`).
- **WoW Forever Horizontal Range Bar (`weave_range.lua`, `main.lua`):** `UnitDistanceSquared` answers only for units in the player's group and not in instanced content (`checkedDistance` is false for an enemy target; Warcraft Wiki `API:UnitDistanceSquared`), so the bar now has a second exact tier: the client's own `C_SwingTimer.IsTargetWithinSwingRange` check (`api.is_target_in_swing_range`, documented on `origin/forever`) paints `<=5 yd MELEE`, `5-35 yd IN RANGE` or `>35 yd OUT` — never an invented yard count between the two bounds. Only when both exact tiers are silent does it show the explicit neutral `--` unknown face (still visible, never a false 0); no target or a non-attackable target still hides it. The driver's 25-consecutive-throw quarantine is recoverable (the driver stays armed, the last paint is kept, the body is skipped for a 10 s backoff that doubles to 60 s, and a success clears it) instead of removing its own `OnUpdate` for the session; and `weave_range.init` is a guarded, idempotent seam with a one-shot `PLAYER_ENTERING_WORLD` retry when an earlier post-init step threw. A `weave=` token in the `/st diag` runtime line names the current gate and state.
- **WoW Forever Power Bar (`power_bar.lua`, `compat.lua`, `diag.lua`):** a restricted (secret) `UnitPower`/`UnitPowerMax` reading — which the arithmetic-safe wrappers still report as `nil` — is read raw by the additive `api.GetPlayerPower` and painted through a real `StatusBar` (`SetMinMaxValues`/`SetValue`, the client's sanctioned pass-through), so the bar stays visible and the value text receives the raw number through `FontString:SetText` (`AllowedWhenTainted`, Text aspect; Blizzard's own `CompactUnitFrame_UpdateStatusText` does `statusText:SetText(UnitHealth(unit))`) instead of hiding with `no-value` or printing `?`; the value is never compared, divided or formatted. Readable rendering is unchanged (same painted width, text and colours; at exactly zero the track now paints empty instead of the old 1 px sliver), and the verbose diag power line reports `value=restricted fraction=?`.
- **Bar Attack-Speed & Timer Text (`utils.lua`):** `st.utils.simple_round` now rounds to the nearest tenth instead of truncating, so the eight one-decimal weapon speeds the old `floor` displayed a tenth low — `1.4`, `1.9`, `2.3`, `2.4`, `2.8`, `2.9`, `3.3`, `3.8` — read correctly, and a true half case rounds up (`1.95 s` remaining shows `2.0`, not `1.9`).
- **Bar Tick Cost (`bars.lua`):** the tick passes its one clock reading into `set_bar_texts` instead of re-reading it, caches the spark decoration (geometry and colour are reapplied only when the live width, height or colour key changes; a per-tick spark does only `Show`/`Hide`), and writes the fill once at the end of the tick instead of twice. The 2026-10-28 resize repaint and the fill-last guarantee are unchanged.

### Hardening

- **WoW Forever Secret-Value Hardening (`compat.lua`, `classes/*.lua`, `hunter_ui.lua`, `hud.lua`, `forever_guide.lua`):**
  - **Restricted reads are unknown, not guessed:** a restricted cooldown, power, target-aura or target-health read now produces `nil` and sets the gather's `inputs_unknown` instead of a confident `0` / "ready" / "absent" / `100 %`, so the Forever guide withholds its advice rather than cueing Judgement, Arcane Shot, Rend, Rip, Rake, Flame Shock or Enrage on data the client is hiding. The same pass fixed a latent paladin crash: the filler mirror's four mana-threshold comparisons could raise on a legitimately nil restricted mana read and now gate on a known-mana flag.
  - **Target-of-target warning (`compat.lua`, `classes/hunter.lua`, `hunter_ui.lua`):** a restricted `UnitIsUnit` result is passed through the client's sanctioned `SetAlphaFromBoolean` sink as a secret boolean instead of being compared or guessed, so the warning still renders (it hides with a one-time notice only where the client lacks the method); the readable path is unchanged.
  - **HUD trinket slots (`hud.lua`):** a restricted item-cooldown read keeps an equipped on-use trinket visible with the existing grey unknown face (no swipe, no countdown text) instead of hiding the slot; a readable passive trinket still hides and a readable on-use trinket still shows as before.
  - **Hunter identity and auras (`classes/hunter.lua`, `hunter_ui.lua`, `forever_guide.lua`):** target identity is routed through the secret-safe `api.UnitGUID` (no raw comparison), the three aura scans walk past a restricted row instead of truncating (Rapid Fire, Frenzy and the aspect icon no longer disappear), and `UnitCreatureType` is guarded — an unknown creature type is not treated as "not undead".
  - **HUD defence in depth (`hud.lua`, `compat.lua`):** the paint re-checks the numeric state fields with the new `api.is_secret` before comparing them; a provider that forgets `restricted = true` and leaks a secret `remaining`/`duration`/`text_remaining`/`start` still lands on the grey unknown face (no swipe, no text) instead of raising and taking the whole HUD tick down.
  - **Compat hardening (`compat.lua`):** the classic `UnitAura` branch gained the `C_Secrets` per-index precheck and a `pcall` (the guard the `C_UnitAuras` branch already had), `GetCombatRating`/`GetCombatRatingBonus` are guarded, and the wave adds `api.get_cooldown_remaining`, `api.spell_aura_may_be_secret`, `api.power_may_be_secret`, `api.health_max_may_be_secret` and a fourth `restricted` return on `api.GetInventoryItemCooldown` — existing wrapper contracts unchanged.

### Changed

- **Version 2.1.8:** `SwedgeTimer.toc` and `main.lua` report version `2.1.8`.
- **One TOC for every client:** the six flavor TOCs (`_Vanilla`, `_TBC`, `_Wrath`, `_Mainline`, `_Cata`, `_Mists`) are removed. `SwedgeTimer.toc` now advertises `## Interface: 11509, 20506, 38002, 40402, 50500, 120100, 120105, 16001` and lists every module once. `LibClassicSwingTimerAPI` stays listed for the classic line and is neutralised on Forever/Retail/Cata/Mists at load time: `swing_lib_gate.lua` pre-registers a tagged LibStub stub above the vendored minor (the library returns at its `NewLibrary` guard) and `swing_lib_gate_release.lua` removes the stub again immediately after the library line, so the shared LibStub registry is never poisoned. `main.lua` treats a tagged stub as absent. `tests/toc_check.lua` and the new `tests/swing_gate_state.lua` pin the contract in both directions.

## [2.1.7]

**Verification status:** all WoW Forever changes in this release are verified offline by the unit suites; in-client behaviour on the Forever client is UNCONFIRMED (no in-client pass is recorded for 2.1.7 yet).

### Fixed

- **WoW Forever Spell Rank Tables Corrected (`forever_guide.lua`):**
  - `FG.SPELLS` now pins the Wowhead Forever ladder set for the 81 tracked spells, replacing the earlier mixed classic/Forever ids: 80 ladders are verified against the Forever DB, with Faerie Fire (Feral) the one documented exception below. `tests/forever_guide_state.lua` pins every id and its order, and `tests/forever_hud_gate_state.lua` proves the corrected primary ids still open their HUD slots.
  - Wrong ids removed: Sniper Shot `14266` (Raptor Strike R8) → `1310687`; Demoralizing Shout `11549`/`11550`/`11551` (Battle Shout) → `11554`/`11555`/`11556`; Searing Totem `10587` (Magma Totem) removed; Claw `9823`/`9827` (Pounce) → `5201`/`9849`/`9850`; Seal of the Crusader `21183` (Judgement debuff) removed and `21082` added; Consecration `20142` (retired) → `20116`; Bloodthrill `1282733` (the APL's Overpower proc aura) → `1289682`.
  - Missing ranks added: Slam R1 `1240193`; Mutilate's eight-id ladder (`399960`, `399961`, `1241582`, `1241584`, `1241585`, `1241586`, `1241588`, `1241590`); Backstab R9 `25300`; Lacerate R1–R5 plus the alternate R4 `1299332`; Primal Bite R1–R4 (`407995`, `1238069`, `1238070`, `1238073`); Ferocious Bite R1 `1328618` and R6 `31018`; Fire Nova `408341`–`408345`; Holy Shield's single rank `20925`; the full Seal of Fury ladder (`1311649`, `1311656`, `20163`, `20419`, `20421`, `20422`, `20423`); Righteous Fury `407627`; the Exorcism `415068`–`415073`, Serpent Sting `425728`–`425737` and Lightning Bolt `408439`–`408477` alternate families; and the Maul/Shred/Swipe rank fills.
  - Also trimmed or deduplicated in the same pass: Multi-Shot, Summon Hawk, Mortal Strike, Bloodthirst, Shield Slam, Hemorrhage, Rupture and Tiger's Fury; Seal of Righteousness gains its `20154` base.
  - **Explicitly unverified — Faerie Fire (Feral):** the ladder is now the operator-ordered union `{16857, 17390, 17391, 17392, 784, 1070, 13424, 13752}`. `16857`/`17390`–`17392` are the classic fallback; `784`/`1070`/`13424`/`13752` are unverified Forever candidates (Faerie Fire (Feral) itself is not present in Wowhead's Forever DB), kept by operator order. This remains the only ladder not verified against Forever data.
- **WoW Forever (Camelot 1.60.1 / Interface 16001) Restricted Aura Reads (`compat.lua`):**
  - `api.UnitAura` asks `C_Secrets.ShouldUnitAuraIndexBeSecret` about the exact unit/index/filter first and skips only a row the client declares secret; the indexed `C_UnitAuras.GetAuraDataByIndex` read is also `pcall`-wrapped, so a restricted row returns nil instead of raising the BugSack error `GetAuraDataByIndex(): Auras cannot be accessed when secret...`.
  - Clients without `C_Secrets` keep reading every row (the probe is a no-op), and a raised read now degrades to absent instead of propagating.
- **WoW Forever Restricted Cooldown Reads (`compat.lua`):**
  - A readable cooldown source is no longer discarded because another source returned secret values: any readable answer, including a readable zero ("not on cooldown"), clears the restricted verdict.
  - When `C_Spell.GetSpellCooldown` returns secret timing, `C_Spell.GetSpellCooldownDuration` is used as a fallback (only when its `HasSecretValues()` answers exactly `false`) and reconstructed into the classic `(start, duration)` shape.
  - `api.GetSpellCooldown` gains a fifth `restricted` return, true only when no readable source answered. Every other read keeps the classic four-value arity, so Era / TBC / Wrath callers observe no shape change.
- **WoW Forever HUD Event Frame (`hud.lua`):**
  - `HUD.build_event_frame` no longer attempts `COMBAT_LOG_EVENT_UNFILTERED` registration on Mainline-code clients (`st.is_mainline`): the register call from tainted code raises `ADDON_ACTION_FORBIDDEN`, which `pcall` cannot catch. Classic Era / TBC / Wrath keep the probed + `pcall`-guarded registration exactly.
- **WoW Forever Next-Action Guide (`forever_guide.lua`):**
  - A restricted cooldown read marks the tick `inputs_unknown` instead of reading as "ready", so the guide withholds its suggestion rather than cueing an ability whose timing the client is hiding.
- **WoW Forever HUD Wiring (`hud.lua`, `option_tables.lua`, `main.lua`):**
  - Forever HUD icons, per-icon option toggles and the HUD template writer/matcher all use the `hud_forever_show_<key>` namespace; the legacy `hud_show_<key>` namespace is unchanged on other families. The option panel also offers the Forever guide's own slot keys (`judge`, not `judgement`).
  - A restricted cooldown read renders as unknown, not ready: the icon is greyed with no swipe or countdown text, even if a provider supplies timing numbers alongside the flag.
  - A nil Forever provider answer no longer falls through to the class provider; that slot stays unknown instead of borrowing a class-module state.
  - `/st diag`'s Forever spell-registry resolution check is gated to `st.family == "FOREVER"`, so classic clients no longer receive Forever-table `MISSING spell` lines.
- **WoW Forever Class-Side Guide Wiring (`classes/rogue.lua`, `classes/druid.lua`, `classes/hunter.lua`, `classes/paladin.lua`):** (offline-verified; in-client UNCONFIRMED)
  - **Rogue:** `raw.inputs_unknown` now threads into the guide's unknown state, so a restricted FG tick suppresses the action instead of displaying it. `mh_is_dagger` is published from the existing `dagger_mainhand()` helper for the Forever spec resolver, and Forever labels/probes use `Venom` while every non-Forever family (TBC/Wrath included) keeps `Envenom`.
  - **Druid:** `prowl_active` is published tri-state — `true`/`false` from the existing merged player-buff walk, `nil` before the walk answers or when a secret-regime miss cannot be read — so the cat opener's Ravage row stays hidden on unknown instead of treating Prowl as down.
  - **Hunter:** `mana_frac` is read on Forever as well, feeding the aspect rows' mana thresholds.
  - **Paladin:** Forever passes FG's `action`/`hold_text` through unchanged (`sor` stays `sor`, `WAIT` stays `WAIT`); the legacy `sob`/`HOLD` display remap is unchanged on every other family.
- **Next-Action Output Reuse (`forever_guide.lua`):**
  - `FG.evaluate` clears `action`, `spell_name`, `judge_call` and `rotation_key` at the start of every tick, so a HOLD / POOL / WAIT branch or a new fight no longer re-displays the previous tick's action or latches the Judgement icon.
- **WoW Forever Guide Leveling, Stalls, Swipes and Shield Wiring (`forever_guide.lua`, `classes/shaman.lua`, `compat.lua`):**
  - Paladin leveling no longer prompts an unlearned Seal: the ret and general fallbacks require Seal of Command / Seal of Righteousness known, else HOLD/WAIT (levels 1-3 hold instead of cueing).
  - Hunter leveling and druid caster no longer blank the guide: an empty Forever priority holds WAIT with a comment that caster DPS is unmodeled.
  - Forever guide slots now carry `cooldown_key` + `swipe_duration` where a matching cooldown input exists, so the Next-Action frame can render cooldown swipes; keyless where no input exists.
  - Warrior Thunder Clap / Cleave arms kept with filed-skeleton markers: `target_count` has no Forever producer, so they stay unreachable rather than removed and widening a fallthrough.
  - Shaman Water Shield uses a dedicated Forever-gated `watershield_due` producer instead of sharing the Lightning Shield line.
  - Druid Shred keeps its allow-but-note comment (`behind_target` has no honest probe); `compat.lua` shapeshift comment exempts Forever.

### Changed

- **Rogue Finisher Renamed to Venom on WoW Forever (`forever_guide.lua`):** `FG.SPELLS.ENVENOM` now carries the client name `Venom` (id `1310703`, unchanged) and `SPELLS_BY_NAME` maps `Venom`. The finisher is reachable through the Forever producer fields `venom_ready`, `venom_buff_active` and `cp >= 3`; the internal Lua key stays `ENVENOM` and the action/slot key stays `envenom`, so the class modules and options surface are untouched.
- **Version 2.1.7:** Every flavor TOC and `main.lua` now report version `2.1.7`.

## [2.1.6]

### Added

- **TBC Anniversary (2.5.6 / Interface 20506) Tank Action Priority Lists & HUD / Next-Action Integration:**
  - **Protection Paladin (`docs/apls_tbc_2026-11-03/paladin/protection/default.apl.json`)**:
    - Implemented authentic TBC Protection APL: Righteous Fury stance upkeep, Holy Shield active mitigation maintenance, Avenger's Shield (`31935`, 30s cooldown) on pull / cooldown, Judgement on cooldown with active seal, Consecration high-threat ground AoE, Holy Wrath against undead/demons, and Hammer of Wrath execute (<20% HP).
    - Replaced Forever-specific placeholder slots (`holy_strike` 10333, `sof` 20423) with authentic TBC Avenger's Shield in `guide_slots_prot` and `HUD_SLOTS_PROT`.
    - Fully verified with 100% revert-proof mutation proofs in `tests/nextaction_state.lua` (659 checks).
  - **Protection Warrior (`docs/apls_tbc_2026-11-03/warrior/protection/default.apl.json`)**:
    - Implemented authentic TBC Protection APL: Emergency defensives (Shield Wall <= 35% HP, Last Stand <= 40% HP), Shield Block active mitigation (<40 rage or missing buff), Shield Slam on cooldown, Revenge reactive procs via `api.IsSpellUsable`, Devastate (Rank 1-3: 20243, 30016, 30022) to build and refresh 5 Sunder stacks, Thunder Clap attack speed debuff upkeep (<= 6s or missing), Demoralizing Shout attack power debuff upkeep (<= 6s or missing), and on-next-attack Heroic Strike / Cleave rage dumps (>50 rage).
    - Dynamic leveling ladder: Level 1-9 Heroic Strike, Level 4 Rend upkeep, Level 6 Thunder Clap, Level 10 Sunder Armor pre-Devastate building/refreshing. HUD automatically displays Sunder Armor when Devastate is unlearned and cleanly hides it once Devastate is acquired.
    - Added dedicated cooldown slots for Shield Wall (`871`) and Last Stand (`12975`) with `HUD_SKIP_GCD` registration.
    - Fully verified with 100% revert-proof mutation proofs in `tests/warrior_state.lua` (2,186 checks).
  - **Feral Bear Druid (`docs/apls_tbc_2026-11-03/druid/feralbear/default.apl.json`)**:
    - Implemented authentic TBC Feral Bear APL: Emergency Frenzied Regeneration (`22842`, <= 40% HP with instant HUD emergency glow), queued Maul ride detection (`RIDE` hold overlay), Mangle (Bear) (`33878`, 6s cooldown) strike, Faerie Fire (Feral) (`16857`) debuff upkeep (<= 6s or missing, `FAERIE FIRE` hold overlay), Demoralizing Roar (`99`) debuff upkeep (<= 6s or missing, intelligently suppressed when Warrior Demoralizing Shout is active), Lacerate (`33745`) 5-stack building and <= 3s refresh, on-next-attack Maul rage dumps (>= 50 rage), and Swipe (`779`) filler (>= 20 rage).
    - Clean leveling ladder: Level 10 Bear Form (Demo Roar upkeep, Maul fallback, smooth rage pooling on low rage), Level 16 Swipe filler, Level 66 Lacerate stack building.
    - Form-aware slot resolution: `resolve_guide_slots` and `get_hud_state` dynamically switch between Cat (7 guide slots, 11 HUD slots) and Bear (7 guide slots, 9 HUD slots) with zero local variable overflow (185 locals, 15 headroom under the 190 ceiling).
    - Fully verified with 100% revert-proof mutation proofs in `tests/druid_state.lua` (1,777 checks).
  - **Cross-Client Discipline & Real-Time Leveling Gates**:
    - All TBC queries strictly adhere to localized English name with numeric ID fallback (`spell_query(id, name)`), while Era strictly queries by numeric ID.
    - Leveling gate is strictly fail-visible: unlearned abilities fall back seamlessly without stalls, errors, or `/reload` requirements.
  - **NextAction UI & Cooldown HUD Enhancements (`nextaction_ui.lua`, `hud.lua`)**:
    - **NextAction UI Known-Spell Knowledge Gating on WoW Forever**: Restored multi-rank spellbook query support in `slot_known_allows` using `nextaction_known_query` across `slot.ids`, ensuring unlearned ability icons and prompts do not display for low-level or leveling characters on WoW Forever.
    - **HUD Known-Spell Query Caching (`hud.lua`)**: Introduced high-frequency query caching with a 1.0s TTL (`KNOWN_CACHE_TTL`) and explicit cache invalidation (`HUD.invalidate_known_cache()`), eliminating repetitive pcall storms during 20Hz frame ticks across multi-rank spell arrays.
    - Verified with new revert-proof mutation tests in `tests/forever_guide_gate_state.lua` and `tests/forever_hud_gate_state.lua`.

### Fixed

- **WoW Forever (Camelot 1.60.1 / Interface 16001) Unified Tank Routing & Duplicate Elimination:**
  - **Eliminated Duplicate Tank Logic**: Completely resolved conflicting duplicate tank/protection logic between `classes/` modules and `forever_guide.lua`.
  - **Paladin Routing**: Removed the `inputs.class ~= "PALADIN"` bypass in `nextaction.lua` so Paladin on WoW Forever routes directly through `forever_guide.lua` for Protection, Retribution, Holy Shock, and Leveling identically to all other classes.
  - **Warrior Protection Gating**: Reordered `resolve_guide_slots` in `classes/warrior.lua` so `is_forever_guide` takes precedence over `if prot then`, preventing WoW Forever Protection Warriors from having their slots hijacked into legacy prototype tables.
  - **Paladin Protection Gating**: Guarded `resolve_guide_slots` in `classes/paladin.lua` with `is_forever_family`, ensuring WoW Forever Paladin guide and HUD slots are governed exclusively by `forever_guide.lua`.
  - **Druid Feral Bear Tank Resolution**: Updated `FG.resolve_druid_spec` in `forever_guide.lua` to recognize `inputs.form_index == 1` for Bear Form (and `3` for Cat Form) as gathered by `classes/druid.lua`, ensuring Bear tanks resolve as `"bear"` rather than falling back to `"caster"`.
  - **Test Suite Parity**: Retained backwards-compatible FCFS priority definitions in `nextaction.lua` to ensure full offline unit test coverage across all test suites without regressions.
- **WoW Forever Pre-Release Contract Alignment & Runtime Hardening (`forever_guide.lua`):**
  - **Flame Shock Spell ID & Rank Alignment**: Corrected Flame Shock base spell ID to `8050` with full rank progression `{ 8050, 8052, 8053, 10447, 10448, 29228 }` (previously mistakenly referencing Earth Shock ID `8042`).
  - **Aspect of the Hawk Action Key Disambiguation**: Disambiguated Hunter Aspect of the Hawk action key from `"hawk"` to `"aspect_hawk"`, avoiding collisions with the 2-minute cooldown `"Summon Hawk"` (`1293241`) action.
  - **Slot-to-Evaluator Action Key Synchronization**: Added `GUIDE_KEY_OVERRIDE` in `FG.get_guide_slots` mapping slot keys to evaluator output actions: `"raptor_strike"` -> `"raptor"`, `"ea"` -> `"expose_armor"`, `"demoralizing_roar"` -> `"demo_roar"`, `"ferocious_bite"` -> `"bite"`.
  - **Live Gather-to-Engine Bridge**: Implemented zero-allocation input bridging (`bridge_inputs`) adapting live inputs from `classes/*.lua` (`gather_guide_inputs`) into `forever_guide.lua` format without mutating input tables. Bridges energy/rage/focus aliases, combo points (`cp` -> `combo_points`), debuff remainders (`snd_remains` -> `snd_remaining`, `rupture_remains` -> `rupture_remaining`, `ff_debuff_remaining` -> `ff_remaining`), active form indices (`form_index == 1` -> Bear, `3` -> Cat), seal states, and lazy live client cooldown queries via `CD_SPELL_BY_FIELD`.
  - **GCD Query Optimization**: Replaced redundant per-slot per-tick API queries in `FG.get_hud_state` with `self.gcd` snapshot caching.
  - **Target Health & Max Health Safe Wrappers**: Routed target health and maximum health queries in execute phase checks (`how`, `execute`) through `st.api.UnitHealth` / `st.api.UnitHealthMax` with raw global fallbacks.
- **Cross-Engine Compatibility & Code Quality Maintenance:**
  - **Addon Name Fallback (`compat.lua`)**: Initialized `st.addon_name = st.addon_name or addon_name`.
  - **Safe Lua 5.1 `table.pack` Shim (`main.lua`)**: Guarded `table.pack` definition with `rawget(table, "pack")` and `rawset` to safely co-exist with existing environment tables.
  - **Druid Debuff Aura Source Filter (`classes/druid.lua`)**: Refined harmful aura scanning for Lacerate to verify `(src == "player" or src == nil)`, ensuring foreign druid bleed debuffs do not interfere with personal maintenance.
  - **Warrior Shield Block Scans (`classes/warrior.lua`)**: Cleaned up unused return variables in `scan_player_shield_block`.
  - **Offline Test Integrity**: Updated regex parsing in `tests/prepull_contract_state.lua` and `tests/spell_query_family_state.lua` to accommodate class loader indentation.
  - **Luacheck Baseline Compliance**: Reached the repository baseline of 2 warnings / 0 errors across all 99 files, and verified 100% test pass rate (56/56 steps) in `tests/run.sh`.

## [2.1.5]

### Added

- **WoW Forever (Camelot 1.60.1 / Interface 16001) Official APL Priority Rotations:**
  - Implemented complete, enterprise-grade Action Priority Lists across all 6 melee classes and specs, calibrated strictly against official simulation priority models (`docs/apls_2026-11-03/`):
    - **Paladin**:
      - **Retribution (`retribution/default.apl.siml`)**: Immediate Judgement on cooldown, Hammer of Wrath execute (<20% HP), Holy Strike (`679`) weaving during empty globals between Judgements, Seal of Command / Seal of Righteousness maintenance, and Consecration / Exorcism mana-managed fillers.
      - **Holy Shock (`retribution/holy_shock.apl.siml`)**: High-priority Holy Shock burst paired with Divine Favor buff tracking.
      - **Protection Tank (`protection/default.apl.siml`)**: Righteous Fury stance upkeep, Seal of Fury (`20423`) high-threat seal maintenance, Holy Shield (`20925`) active mitigation, Judgement on cooldown, Consecration high-threat ground AoE, Holy Strike weaving, and Hammer of Wrath execute.
      - **Leveling Fallback**: Smooth Level 1–20 progression using Seal of Righteousness, Judgement, and baseline Holy Strike learned at level 6.
    - **Warrior**:
      - **Arms (`dps/arms.apl.json`)**: Bloodthrill (`1282733`) Overpower procs & dodge triggers (only 5 rage), Mortal Strike priority, Whirlwind, Slam cast-weaving on swing window, Rend upkeep, Execute burn (<20% HP), and Cleave & Heroic Strike dumping (>60 rage).
      - **Fury (`dps/fury.apl.json`)**: Bloodthrill Overpower weaving within the 5–73 rage window, Whirlwind, Bloodthirst, Execute burn, and Cleave & Heroic Strike dumping.
      - **Protection Tank (`protection/default.apl.json`)**: Emergency defensives (Shield Wall <= 35% HP, Last Stand <= 40% HP), Shield Block (<40 rage or missing buff), Shield Slam, Revenge reactive procs via `api.IsSpellUsable`, Sunder Armor 5-stack upkeep and refresh (<=10s), Thunder Clap debuff, Demoralizing Shout debuff, Rend, and on-next-attack Heroic Strike / Cleave rage dumps.
      - **Leveling Fallback**: Clean fallback to Battle Shout, Rend, Sunder Armor, and Heroic Strike for low-level warriors.
    - **Hunter**:
      - **Melee Survival (`dps/melee.apl.siml`)**: Strictly gated on the `Strider Kick` talent (`1317257`) or user toggle (never auto-assumed by proximity). Raptor Strike queue, Hunter's Mark upkeep, Mongoose Bite reactive procs, Strider Kick on cooldown, Immolation Trap on cooldown, Summon Hawk (`1293241`), and Wing Clip filler.
      - **Ranged Weave & Turret (`dps/clean_weave.apl.siml`, `dps/turret.apl.siml`)**: 4.0s Sniper Shot (`14266`) opener/cooldown, Aimed Shot (`19434`), Multi-Shot, Arcane Shot, Serpent Sting upkeep, Summon Hawk, Hunter's Mark, and Auto Shot shot-weaving endzone clip protection.
      - **Leveling Fallback**: Low-level hunters cleanly prioritize Serpent Sting, Arcane Shot, Hunter's Mark, and Raptor Strike without stalling.
    - **Rogue**:
      - **Spec-Aware Builders (`dps/default.apl.json` & `dps/presets.ts`)**: Mutilate (`1241584`) 2-dagger builder, Combat Daggers Backstab (`53`), Subtlety Hemorrhage (`16511`), and Combat Swords/Maces Sinister Strike (`1752`).
      - **Finishers & Upkeeps**: Slice and Dice (`6774`) attack speed priority, Envenom (`1310703`) Deadly Poison stack consumption, Rupture (`1943`) bleed upkeep based on Target Time-to-Die (TTD >= 10s), and Eviscerate (`2098`) direct damage finisher.
      - **Utility & Defense**: Riposte (`14251`) reactive parry procs with HOLD overlay prompts, and Expose Armor (`8647`) armor reduction upkeep when designated.
      - **Leveling Fallback**: Sinister Strike, Slice and Dice, and Eviscerate fallback when advanced talents/poisons are unlearned.
    - **Druid**:
      - **Feral Bear Tank (`feralbear/adaptive.apl.json`)**: Emergency defensives (Barkskin `22812` <= 40% HP, Frenzied Regeneration `22842` <= 30% HP), Enrage rage generation, Faerie Fire (Feral), Demoralizing Roar, Primal Bite (`1238070`) on cooldown, Lacerate (`1235827`) 5-stack maintenance, Swipe AoE filler, and Maul queue (>50 rage).
      - **Feral Cat DPS (`feralcat/adaptive.apl.json`)**: Stealth Ravage (`6785`) opener, Faerie Fire (Feral), Omen of Clarity Clearcasting free Shred priority, 5-combo point Rip (`1079`) bleed upkeep, Ferocious Bite (`22568`) finisher, Tiger's Fury (`5217`) damage buff, Rake (`1822`) bleed upkeep, Shred (`5221`) behind target, and Claw (`1082`) fallback builder.
      - **Leveling Fallback**: Bear Maul & Swipe fallback; Cat Claw & Ferocious Bite fallback.
    - **Shaman**:
      - **2H Enhancement DPS (`enhancement/testing.build.json` & `enhancement/presets.ts`)**: Strictly verified 2-Handed weapon rotation (item slot 15 empty: no Dual Wield, no Lava Lash on WoW Forever).
      - **Rotation Priority**: Flame Shock (`8052`) DOT upkeep, Stormstrike (`17364`) nature vulnerability, instant Lightning Bolt (`403`) at 5 stacks of Maelstrom Weapon (`408505`), Earth Shock (`8042`) burst, Fire Nova (`408345`) AoE burst, Totem upkeep (Strength of Earth, Grace of Air / Windfury, Mana Spring, Searing Totem), and Water Shield (`408510`) / Lightning Shield maintenance.
      - **Leveling Fallback**: Rockbiter/Windfury weapon buff upkeep, Searing Totem, Lightning Bolt weave, Earth Shock, and Flame Shock.
- **Offline Test Suite Expansion (`tests/forever_guide_state.lua`)**:
  - Expanded unit test assertions from 65 to 132 comprehensive checks, asserting every class, spec, defensive threshold, execute phase, and leveling fallback across all 6 classes under offline simulation.
- **Specialization & Tanking Support (Melee Specs across WoW Forever, TBC, Wrath, Era):**
  - **Protection Paladin:** Added dedicated Protection Paladin FCFS decision engine (`FCFS_ORDER_PROT_FOREVER` & `FCFS_ORDER_PROT`) and HUD layout with auto shield detection (`api.is_shield_equipped()`). Prioritizes Shield Slam, Holy Shield upkeep, Righteous Fury upkeep, Judgement, Consecration, and Holy Wrath. Dynamic `resolve_guide_slots` preserves Retribution contract defaults while swapping into Protection slots at post-init.
  - **Protection Warrior:** Added dedicated Protection Warrior decision engine (`evaluate_prot`) with auto shield detection and spec selection (`auto`, `protection`, `arms`, `fury`). Prioritizes emergency cooldowns (Shield Wall <= 35% HP, Last Stand <= 40% HP), Shield Block (< 40 rage or missing), Shield Slam, Revenge (reactive block/dodge/parry proc via `api.IsSpellUsable`), Sunder Armor upkeep (stacking initial 5 and refreshing <= 10s), Thunder Clap debuff, Demoralizing Shout debuff, Rend, and on-next-attack Heroic Strike / Cleave rage dumps.
  - **Druid Feral Bear & Cat Leveling:** Added Maul spellbook knowledge gate (`inputs.maul_known`) to Bear Form decision logic. In Bear Form, prevents unlearned Maul from being recommended to low-level druids, seamlessly pooling rage or falling back. In Cat Form, smoothly falls back to Claw as the core builder and Ferocious Bite as the leveling finisher when Shred or Rip are unlearned.
  - **Rogue Defensive State & Leveling:** Added Riposte parry proc detection (`api.IsSpellUsable` on Defensive State 5302) with reactive HOLD overlay prompt (`RIPOSTE`). Fixed leveling finisher stall where leveling rogues with unlearned Rupture and unknown target TTD were previously blocked on "POOL" at 5 combo points; now smoothly falls back to Eviscerate without stalling.
  - **Shaman Enhancement Leveling:** Audited low-level progression gates for Enhancement Shamans from level 1 to 60. Cleanly falls back to Earth Shock, Lightning Bolt weave, Lightning Shield, and Searing Totem when higher-level abilities (Flame Shock, Stormstrike, Lava Lash, Maelstrom Weapon) are unlearned.
- **Dynamic Leveling Progression for HUD & Next Actions Across All Classes:**
  - Implemented dynamic spell knowledge gating across the Next Action Guide and Cooldown HUD (`hud.lua`), suppressing prompts, idle openers, and icon slots for unlearned abilities, fillers, and judgement cues across all classes (Hunter, Paladin, Warrior, Rogue, Shaman, Druid).
  - Leveling gate is fail-visible: only a confirmed unlearned status hides an ability, while unqueryable or ambiguous states remain visible.
  - Universal Cross-Client Name-vs-ID Discipline: Classic Era (`st.family == "ERA"`) strictly queries by numeric spell IDs, while all other clients (TBC Anniversary, WotLK Titanforge, WoW Forever, and modern families) strictly query by localized names with verified numeric ID fallbacks.
  - Lower Rank Recognition: Leveling characters knowing lower ranks of an ability have that ability recognized and allowed dynamically (via localized name on non-Era and numeric ID on Era) without requiring max-expansion DBC ranks.
  - Real-time progression without `/reload`: training a new spell rank at a class trainer or allocating talent points automatically unlocks both HUD icons and Next Action prompts on the very next frame tick.
  - Smooth Rotation Fallbacks During Leveling:
    - **Hunter**: When Kill Command is not learned (level < 66), the guide smoothly yields to Multi-Shot, Arcane Shot, and Serpent Sting without stalling or falling into the Auto Shot HOLD overlay.
    - **Warrior**: Gated Overpower, Execute, Bloodthirst, Whirlwind, Mortal Strike, Sunder, and Rend on spellbook knowledge. Leveling warriors without high-level abilities smoothly fall back to Heroic Strike, Cleave, Rend, and Sunder without getting stuck.
    - **Shaman**: Gated Stormstrike, Lava Lash, Earth Shock, Fire Nova, Strength of Earth, Mana Spring, Searing Totem, and Magma Totem on spellbook knowledge. When high-level abilities are unlearned, smoothly falls back to Earth Shock, Searing Totem, and Lightning Bolt weave.
    - **Druid**: Gated Bear Mangle, Cat Rip, Cat Mangle, Ferocious Bite, and Shred on spellbook knowledge. In Bear form, pools rage when Mangle is unlearned. In Cat form, smoothly falls back to Claw as the core builder across TBC, Wrath, Forever, and Era whenever Shred or Mangle are unlearned.
    - **Rogue**: Builder candidate chain dynamically falls back to Sinister Strike when high-level builders (Saber Slash, Mutilate, Hemorrhage) are unlearned. Rupture smoothly falls back to Eviscerate when unlearned, and Slice and Dice is gated on spellbook knowledge.
    - **Paladin**: Crusader Strike, Divine Storm, Judgement, Exorcism, and Consecration are gated on spellbook knowledge. On WoW Forever, Retribution paladins without Exorcism (learned at level 24) smoothly fall back to Consecration (learned at level 20) and seal management without stalling or requesting unlearned spells. Both Retribution and Protection paladins dynamically adapt during leveling.
- **WoW Forever Cooldown HUD & Next-Action Guide Integration (Offline Verified, Pre-Launch):**
  - Integrated simulation-calibrated Action Priority Lists from `forever_guide.lua` across all 6 class modules (`classes/{paladin,warrior,hunter,rogue,druid,shaman}.lua`) for the upcoming WoW Forever client (`st.family == "FOREVER"`, Interface 16001). Since the server has not yet launched, all mechanics are verified strictly offline using TBC/Era runtime contracts and unit test suites.
  - Leveling gate integration in `HUD.spell_known_allows(slot)`: checks `slot.ids` (all ranks) dynamically via `api.is_spell_known(id)`. Unlearned abilities remain hidden on the Cooldown HUD; learning new ranks or talents dynamically unhides the ability without requiring `/reload`.
  - Usable-only trinket visibility (`HUD.trinket_usable` in `hud.lua`): empty trinket slots and passive stat sticks (where `GetInventoryItemCooldown` returns `enable = 0`) remain hidden, displaying only when equipped with active on-use cooldowns or tracked proc buffs.
  - Added mutation-verified offline test suite `tests/forever_hud_gate_state.lua` (102 checks with confirmed non-zero mutation proof exits across all 6 classes) covering dynamic leveling gate progression, multi-rank ID lookups, unusable trinket suppression, and Next Action leveling fallback paths for Paladin, Warrior, Hunter, Rogue, Druid, and Shaman.
  - Preserved cross-engine isolation: Era, TBC, and Wrath runtime branches and offline pins remain completely untouched and passing.

## [2.1.4]

### Added
- **Hunter Visual Enhancements & Cooldown HUD Text Recovery:**
  - Ranged Bar Class Color: The hunter ranged bar progress fill now uses authentic hunter raid class color (`#ABD473`) instead of generic bar tints.
  - Solid Red Auto Shot Endzone: Auto Shot cast endzone renders solid red (`COLOR_CAST_ENDZONE`) to clearly indicate unshootable / clip intervals without confusing shifting colors.
  - Cooldown HUD Countdown Text Recovery: HUD countdown text now defaults to visible (`db.hud_show_text ~= false`) even when profile settings lack an explicit boolean, ensuring countdown numbers display on cooldown icons.
- **WoW Forever (Camelot / 1.60.1) Native Swing & Range Integration:**
  - Integrated native `C_SwingTimer` API and `PLAYER_SWING` event monitoring for WoW Forever (`WOW_PROJECT_CAMELOT = 18`, interface `16001`), providing hardware-accurate swing pacing without classic combat log dependencies.
  - Added native combat-reach and target hitbox range checking via `C_SwingTimer.IsTargetWithinSwingRange` and `C_SwingTimer.EnableRangeCheck`.
  - Added `hide_blizzard_swing_timer` toggle in General Behaviour settings to suppress redundant built-in `Blizzard_SwingTimer` frames and synchronize the `showSwingTimer` CVar.
- **Raid Class Color API Integration:** Base swing progress fill colors for all classes now dynamically resolve
  from the client's `RAID_CLASS_COLORS` API (via normalized `st.api.get_class_color` / `get_class_color_table`),
  seamlessly leveraging `C_ClassColor.GetClassColor` where available.
- **Classic Era Shaman Blue Guard:** Enforced canonical Shaman blue (`#0070DE` / `0, 0.44, 0.87`) on Classic Era
  and Season of Discovery clients for both the mainhand swing bar and the Enhancement weave spark, preventing the
  unpatched vanilla pink (`#F58CBA`) palette from displaying on Shamans.
- **Class Color Profile Migration (`class_color_defaults_214`):** Safely migrates existing saved player profiles
  carrying legacy generic purple (`{93, 58, 207}`) or druid blue (`{18, 85, 201}`) default bar colors to their
  authentic class colors upon login, while strictly preserving custom player color configurations.
- **Workspace Diagnostics Configuration:** Retained `C_UIFileAsset` in `.luarc.json` under `Lua.diagnostics.globals`
  to support modern client UI file asset probing without false-positive IDE diagnostic warnings.

### Changed

- **Universal Power Bar Architecture & Class File Consolidation:**
  - Unified all classes under the universal `power_bar.lua` bar frame, eliminating duplicate bar implementations.
  - Eliminated orphaned root `druid_energy.lua` and its standalone test `tests/druid_energy_state.lua`.
  - Consolidated Druid energy tick tracking, 2.0-second server cadence math, Cat Form deficit counters, form change
    listeners, and debuff timing calculations directly into `classes/druid.lua` inside the `st.class_loaders["DRUID"]`
    closure, establishing architectural parity with Rogue (`classes/rogue.lua`).
  - Updated all 7 load-order TOC files (`SwedgeTimer.toc`, `SwedgeTimer_Vanilla.toc`, `SwedgeTimer_TBC.toc`,
    `SwedgeTimer_Wrath.toc`, `SwedgeTimer_Mainline.toc`, `SwedgeTimer_Cata.toc`, `SwedgeTimer_Mists.toc`) to remove
    references to `druid_energy.lua`, and cleaned up test runners across `tests/`.

### Fixed

- **Third-Party Cooldown & Addon HUD Isolation:**
  - Completely suppressed OmniCC, ElvUI, Tukui, and native Blizzard action bar countdown numbers from colliding with
    SwedgeTimer cooldown frames across HUD (`hud.lua`), next-action guide (`nextaction_ui.lua`), paladin tracking
    (`classes/paladin.lua`), and practice trainer cooldown frames (`practice_ui.lua`).
  - Applied isolation flags: `noCooldownCount = true`, `noOCC = true`, `hideText = true`, and conditional
    `SetHideCountdownNumbers(true)` where supported by the client engine.
  - Decoupled inherited global `FontObject` templates on cooldown text strings and power bar labels, preventing external
    UI skinning addons from corrupting SwedgeTimer typography and text placement.
- **Strict LSP Diagnostic Warnings & Type Safety (Zero Comment Suppressions):**
  - Resolved all Language Server diagnostics through proper type contracts, function signatures, and defensive guards
    without using `--` comment suppressions or disabling lint rules.
  - `bars.lua:591` (`redundant-parameter`): Updated `ST.configure_bar_size_and_positions` docstring annotation in
    `option_tables.lua` to accept optional `width_override?: number, height_override?: number` parameters matching
    the runtime caller signature used by the hunter melee stack.
  - `classes/paladin.lua:6100` (`param-type-mismatch`): Fixed `ST.PALADIN.practice_default_order` to pass valid table
    references `(ST, {})` to `practice_default_mode(self, ctx)` instead of `nil, nil`, resolving table type requirements.
  - `classes/warrior.lua:5974, 6029, 6053, 6057` (`need-check-nil`): Added explicit `if not inputs then return nil end`
    guards after calling `practice.inputs(self, ctx, {})` in drills `warrior_ww_delay`, `warrior_sunder_upkeep`, and
    `warrior_execute_burn`, preventing nil dereferencing on `bt_remaining`, `sunder_stacks`, `target_health_pct`, and
    `execute_pct`.
  - `classes/shaman.lua:4690` (`cast-local-type`): Refactored `ST.SHAMAN.practice_neutral_set` to cleanly return typed
    family buckets and flat published tables without reassigning a table variable as boolean.
  - `config.lua:119-213` (`inject-field`): Replaced ambiguous `AceAddon` type casting with `---@class ST: AceAddon` and typed migration flags (`APPEARANCE_DEFAULTS_MIGRATION_FLAG`, `APPEARANCE_OLD_BACKGROUND_COLOR`, `migrate_appearance_defaults`, `CLASS_COLOR_DEFAULTS_MIGRATION_FLAG`, `OLD_GENERIC_BAR_COLOR_90`, `OLD_GENERIC_BAR_COLOR_85`, `OLD_DRUID_BAR_COLOR`, `migrate_class_color_defaults`), eliminating language server field injection warnings on the addon root.
  - `practice_progress.lua:1266` & `practice_stats.lua:504` (`cast-local-type`): Annotated `P.json_safe` and `S.json_safe` with `---@param value any` and `---@return any`, assigning `out[i] = false` directly rather than retyping the local `item` variable when preserving dense JSON arrays.
  - `widgets.lua:221` (`inject-field`): Declared `---@class DropdownSoundPreviewWidget: AceGUIWidget` with `SetList` method signature, cleanly typing the wrapped AceGUI dropdown widget constructor.
- **Enterprise-Grade Test Hardening (True Negative & Failure Assertions):**
  - Refactored test suites to verify genuine failure conditions rather than passive execution.
  - Merged Druid energy tick tests into `tests/druid_state.lua` with active negative assertions: out-of-bounds rejection,
    NaN and nil parameter safety, clock skew / hitch clamping, and energy spike damping on instant resource gains.
- **Linux Environment Line Ending Standardization:**
  - Enforced Unix LF (`\n`) line terminators across all repository files, stripping unintended Windows CRLF returns.

## [2.1.3]

### Added

- Hunter ranged-distance bar: a standalone horizontal bar in its own frame that reads exact yards from
  the client (`api.UnitDistance`): full at 5 yd or closer, empty at 35 yd for hunters (30 yd for other
  classes), with a yards label plus MELEE / IN RANGE / OUT. On by default for hunters, opt-in for every
  other class; with no target or an unreadable distance it hides instead of painting a false 0.
- Moving practice timeline: class drills and scenarios now show a cue strip with a fixed playhead at 25%
  of the strip and a 10 s horizon, so upcoming cues travel to the playhead while the run is live. The
  strip wears the reference layout at screen scale — the track spans the client and the 600 px track is
  only the fallback for a client that reports no screen width: a left rail with one icon and name per
  lane (SoB / Melee / CS / Consec / SoC / Judge for the paladin's twist sim), a ruler with `m:ss` labels
  and full-height second gridlines that scroll under the fixed playhead, chunky alternating lane rows, a
  close button, and a default position near the top of the screen, plus the current rotation band (label
  - sequence icons) above the ruler. Cues use the practice panel's own action art, including the twist's
  split Command/Blood icon. Practice opens BOTH frames — the moving timeline and the control panel — and
  the top timeline is the drill's timing surface. The old post-fight log does the same full-width job
  behind the panel's opt-in **Timeline** button.
- The practice panel reads like the reference trainer: the bind hint under the icon grid, a **(Reset)**
  link that restores the session keybinds, a hairline between each block, the Bloodlust / Haste Pot pair
  as two equal halves, and the reference's order — haste pair, the **Practice Rotation** picker, **Start
  Fight**, **Timeline**. The port's own readouts (fight timer, score, resource, DST toggle and the live
  hint) sit below that block; a class drill panel keeps just its own binds, with no Reset link.
- Practice XP is earned per graded press on that timing surface (the sim's twist window / each class's
  drill timing), through the existing progression path; opening the trainer or letting it idle earns
  nothing.
- Per-client spell querying: state queries use numeric ids on Classic Era (Season of Discovery included)
  and localized spell names first on TBC Anniversary and WotLK Titanforge, with the id form kept as the
  fallback. The hunter range tokens now follow the same matrix (Era ids; TBC/Wrath names with the id
  fallback) and the on-next-attack queue probes cold rank ids instead of silently skipping them.
- Power bar: a thin primary-resource bar in the slot under the melee stack. It anchors to the **offhand
  row** whenever the class can use an offhand — even while that hand is idle and hidden — otherwise to
  the mainhand row; it re-points when the owning row is moved, and it hides when no melee bar is on
  screen. It reads the client's primary power type, so hunters/paladins/shamans show mana, warriors and
  bear druids rage, rogues and cat druids energy, and focus is shown where it is primary. Default
  height 14 px (range 10-30); the value text can be hidden.
- Hunter melee stack: the thin mainhand/offhand bars are pinned under the ranged bar at its width
  (ranged -> MH -> OH). It is a stable layout (not tied to the cast-bar window) and has an off switch
  that restores each hand's own saved width and LibWindow position.
- Melee pair height (Positioning): one control sizes the mainhand and offhand bars together (6-60 px,
  one-pixel step), and clearing it hands each bar back to its own saved height. Only a class that owns
  both melee hands gets the block. The offhand's own Height and Width fields show the size that is
  actually rendered for that hand and are locked, so neither can claim to size a bar it does not size.
- `/st diag` now prints a per-hand BAR STATE line — built / shown / alpha / tick / the cycle fields
  (start, speed, ends_at, now, progress) / full / paused / dead / fill width / saved position, plus the
  hunter queue flags — a one-line power-bar state (anchor row, shown, width and height, live power type
  and value, and the reason it is hidden), a `why=` reason token on every hidden hand, the activity
  gate and receipt fields (`gate=`, `active=`, `win=`, `left=`, `src=`), and a quarantine line naming
  each guarded site with its throw count. A silent bar, a stuck gate or a quarantined subsystem is now
  visible without an error being thrown.

### Changed

- Offhand and ranged bars are activity-driven: they show after a real offhand swing or a real ranged
  shot (Auto Shot, Shoot, Throw, Shoot Wand), or while Auto Shot is armed, and hide again after about
  two cycles of that hand (clamped to 1.5-8 s). Being in combat with a target no longer shows them, and
  the hand's configured show rule still applies on top of the gate.
- The ranged bar is placed once, on the first login after the update, in the standard layout above the
  melee stack, for every class that owns a ranged hand — a dragged or scaled saved row included. A row
  already in place is left untouched (no write, no notice); a move announces itself once in chat. A
  drag made after that pass is respected, and the row directly under the melee stack stays reserved for
  the power bar.
- The offhand bar takes the mainhand's width and height instead of its own saved keys (the hunter melee
  stack still overrides both melee hands to the ranged bar's width); changing the mainhand's size
  resizes a built offhand in the same pass.
- A completed ranged shot no longer restarts the melee swing: the addon arms the vendored swing
  library's own `preventSwingReset` field for every class (not only hunters), and Shoot, Throw and
  Shoot Wand are no longer in the addon's own melee-reset list. The library itself stays stock, so its
  Wrath and Cata branches' own reset entries remain the documented residual. The hunter melee cast-bar
  re-anchor is retired; the melee stack anchors to the ranged bar itself, so it cannot hop during the
  Auto Shot window.
- The bar backdrop is opaque by default (alpha 1.0). A one-time migration raises only a profile that
  still holds the untouched old default; custom colours and theme presets are left as saved.
- The paladin practice session now opens STOPPED (the reference trainer's behaviour): **Start Fight**
  begins the fight and the timeline, **Stop Fight** freezes both. Class drills whose session starts its
  own fight run the timeline from the session start and freeze on Stop.
- Options → Practice offers **Open Practice Panel** (all six class pages): it opens or raises the
  trainer and never ends the session. Closing the options window leaves practice running; only the
  practice panel's X stops it.
- The hunter cast window now speaks one colour language: the Auto Shot zone and the cast bar's own
  overlay are white while a cast is safe and red while it is not (was green/red), the safe face carries
  more alpha (0.55), and the latency end-slice uses the same red at the same alpha. A Steady Shot's
  landing is easier to read against the zone.
- The next-action guide ships in its own frame at the upper right of the screen by default (127, -65
  from the screen centre; was 0, -180), so a fresh profile starts where the operator keeps it. It stays
  locked by default like every other movable frame; its own lock toggle unlocks dragging.
- Bar width defaults to 275 px for every hand on every class: the per-class 200 px overrides are gone, so
  the shared default is the only authority and a fresh profile matches the shipped layout.
- Bar opacity is one value everywhere (0.9): the shared fill default moved up from 0.85 so it matches
  every hand's own fill, and the hunter's melee rows now use the shared 2 px border, so the thin stack
  reads as the same widget as the ranged row above it.

### Fixed

- Restored the HU-23 LibRangeCheck protected-call removal after the 2026-10-25 re-vendor: the library no
  longer reaches the client's protected `CheckInteractDistance`.
- WoW Forever swing engine: a weapon swap restarts the cycle at the equipped speed instead of leaving a
  stale cycle, and world entry STOPs live cycles before clearing them instead of dropping a visible bar.
- Class practice drills previously had no timeline at all; the moving cue strip now appears in every
  session.
- Base TOC restored to the classic-line fallback (11509, 20506, 38002); it must not advertise a
  mainline interface while shipping LibClassicSwingTimerAPI. The TOC check now exact-matches both the
  base and Mainline interface lists.
- The offline harness no longer writes the tracked luac.out artifact (luac output goes to a temp file),
  and the repo .gitattributes no longer excludes the required Media fonts/statusbar/sounds from a
  git-archive release.
- Hunter mainhand fill: the Raptor Strike / Steady Shot queue tint now paints only while a live
  main-hand melee cycle exists, and every clear path repaints — the swing that consumes the queue,
  combat exit, a target change and the current-spell clear. Ranged play can no longer recolour the
  main-hand fill; shipped defaults are unchanged (Raptor ON, Steady OFF).
- Classic Era: `COMBAT_RATING_UPDATE` no longer raises. The Classic Era client does not define
  `CR_HASTE_SPELL`, so the haste rating is now read through the literal rating index 20 and the rating
  reads are pcall-guarded, with a nil reading treated as unknown rather than a crash.
- The one-time opaque-backdrop migration now actually reaches a saved profile: the done marker and the
  class row are read with `rawget` and the marker must be the plain boolean `true`, so AceDB's defaults
  metatable can no longer answer the read with a table and skip the migration.
- Hunter cast bar, range helper and proc badges no longer stop painting when the ranged bar is hidden:
  the visual set is driven from the hand's anchor frame as well, and it stays inert when the ranged
  hand is disabled.
- Hunter mainhand bar no longer sits fully filled for the whole cycle: a layout pass that resizes the
  melee rows (the hunter melee stack) now repaints the fill from the hand's live progress instead of
  resetting it to the full bar width, the stack only resizes when the target width really changes (a
  hairline width read no longer re-runs the resize every frame), and the tick re-asserts its own fill
  as the frame's last write, so nothing that runs mid-tick can leave a full-width fill behind. The bar
  empties and fills with its own swing instead of reading like a bar that never starts.
- HUD icons draw one cooldown number instead of two: the icon's cooldown frame suppresses the client's
  own countdown and is marked `noCooldownCount` (the inter-addon flag external countdown text reads), so
  the HUD's own text is the single source. The cooldown swipe itself is untouched.
- Cross-addon cooldown text hardening: full suppression flags (`noCooldownCount`, `noOCC`, `hideText`,
  and `showCooldownNumbers = false`) are now asserted on both the cooldown frames and their parent
  containers across all modules (HUD icons, Next Action guide, Paladin tracking bars, Practice panels).
  HUD cooldown frames also re-assert native countdown suppression (`SetHideCountdownNumbers(true)`)
  before every `SetCooldown` invocation and upon cooldown clear, preventing external countdown addons
  (OmniCC, ElvUI, Tukui) from hooking, styling, or misattributing cooldown timers between SwedgeTimer
  and other addons. HUD and power bar FontStrings decouple from global font templates
  (`SetFontObject(nil)`), ensuring text formatting stays private and does not leak across addons.
- Swing timing now lives on ONE clock domain. The precise clock still drives the tick, but it re-anchors
  to `GetTime()` on every read instead of learning the offset once (a loading screen pauses `GetTime()`
  while the precise clock runs, so a frozen offset drifts by the loading time), and every swing-engine
  timestamp is converted onto our axis at the handler boundary (the bias is measured from a START, which
  always spans exactly one weapon speed). A mainhand cycle now spans exactly its speed - the operator's
  readout showed `speed=3.50` with only 3.10 s of bar - so the fill, the countdown text and the queue
  tint all read the same cycle.

### Hardening

- Two code-grounded audits (core performance/reliability; feature/class) filed on the bench; no
  user-facing claim beyond the fixes above.
- AceDB settings reads: the class table, the sound-channel lookups, the latency, GCD-marker and
  bar-full-delay keys, the appearance migration's marker and the ranged-placement latch are read with
  `rawget` and type-checked, so a missing key can no longer create and persist a defaults table on the
  profile.
- Sound: a saved sound channel must be a string (otherwise `"Master"`), and the options preview and the
  paladin twist cue run the client's play/stop calls inside `pcall`, so a corrupt sound setting cannot
  error out of the addon (a corrupt cue choice now falls back to the shipped cue instead of playing
  nothing).
- Every 2026-10-28 change above is proven by the offline suites and source review only — the in-client
  pass on TBC Anniversary and Classic Era is still owed.

## [2.1.2]

### Added

- One-Click Modern Theme Presets: instant visual styling under Bar Appearance options:
  - Midnight Velvet (deep midnight blue/black bar with subtle outline)
  - Clean Glassmorphic (semi-translucent modern glass with refined border)
  - Minimalist / ElvUI (flat, high-contrast borderless aesthetic)
  - Classic Retro (traditional Blizzard UI styling)
- Animated Leading Edge Spark: an active glowing spark traveling at the swing bar's leading edge for crisp timing feedback (configurable width and color, enabled by default).
- Swing & Shot Completion Flash: a smooth tactile flash pulse on swing completion and shot releases providing instant visual confirmation (configurable duration and color, enabled by default).
- Cooldown HUD Quick Styling & Template Switcher in Design Mode:
  - Curated layout template dropdown ("Custom", class-specific presets) accessible directly within `/st design`.
  - Live HUD geometry and appearance controls in Design Mode (Orientation, Icon Size, Icon Spacing, Match Bar Width, Scale, and Zoomed Icons) with immediate visual feedback while positioning overlays.
- Zoomed / Borderless Icons: opt-in edge-to-edge icon display (`hud_zoom`) that cleanly trims the 5% Blizzard outer icon border.

### Changed

- Refined default bar transparency to 0.85 across all hands, and 0.90 for Hunter ranged/melee bars.
- Cooldown HUD frame is now selectable, highlighted, and freely draggable in Design Mode (`/st design`) without collapsing, with robust lock and relock state preservation.
- Talent Specialization Selection: enforced mutual exclusivity between Spec 1 and Spec 2 (`enable_spec1` vs `enable_spec2`) so only one spec profile is active at a time (defaults to Spec 1 on, Spec 2 off).

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
