# ⚔️ SwedgeTimer

<p align="center">
  <b>The Universal Swing Timer, Next-Action Guide & Cooldown HUD for World of Warcraft</b><br>
  <i>One single download — automatically optimized for every client flavor!</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Status-Feature%20Complete-brightgreen?style=for-the-badge" alt="Status">
  <img src="https://img.shields.io/badge/WoW%20Forever-1.60.1%20Ready-blueviolet?style=for-the-badge" alt="WoW Forever">
  <img src="https://img.shields.io/badge/Classic-Era%20%7C%20SoD%20%7C%20TBC%20%7C%20Wrath-blue?style=for-the-badge" alt="Classic Support">
  <img src="https://img.shields.io/badge/License-GPLv3-orange?style=for-the-badge" alt="License">
</p>

---

## 🌟 Overview

**SwedgeTimer** gives you frame-perfect combat timing and rotation guidance across all your characters. Designed for competitive raiders, levelers, and PvPers alike, SwedgeTimer combines cycle-accurate swing bars, dynamic Auto Shot tracking, an intelligent Next-Action priority engine, and an offline Practice Gym into a lightweight, plug-and-play addon.

No more separate downloads for Era, TBC, Wrath, or **WoW Forever** — SwedgeTimer automatically detects your client and loads the exact right engine, spell data, and priority rules on login!

SwedgeTimer provides dedicated, cycle-accurate rotation engines and real-time leveling support for **6 classes** across **16 distinct raid specializations and leveling paths**:

- **<span style="color:#F58CBA">Paladin</span>** (3 specs + leveling): Retribution, Holy Shock (Shockadin), Protection Tank
- **<span style="color:#C79C6E">Warrior</span>** (3 specs + leveling): Arms, Fury, Protection Tank
- **<span style="color:#ABD473">Hunter</span>** (2 specs + leveling): Melee Survival, Ranged Weave & Turret
- **<span style="color:#FFF569">Rogue</span>** (4 specs + leveling): Mutilate, Combat Daggers, Subtlety Hemorrhage, Combat Swords / Maces
- **<span style="color:#FF7D0A">Druid</span>** (2 specs + leveling): Feral Bear Tank, Feral Cat DPS
- **<span style="color:#0070DE">Shaman</span>** (2 specs + leveling): 2H Enhancement DPS, Elemental Spell-Weaving

> [!NOTE]
> **Universal Flavor Dispatch**: SwedgeTimer automatically detects whether you're playing on WoW Forever, Era, SoD, TBC, or Wrath, loading the exact right engine, spell tables, and rotation models on login with zero manual configuration.

---

## 🚀 What's New in v2.2.0

> [!IMPORTANT]
> **<span style="color:#FFD700">Secret-Value Access Hardening & Release Refresh!</span>** SwedgeTimer v2.2.0 puts every client read that feeds a comparison, an arithmetic step, text formatting or a timer behind the client's own `canaccessvalue`/`canaccessallvalues` probes (cooldown start/duration, cast start/end, attack speeds, target name/GUID, the cast-bar key), nil-hardens the UI, practice and options paths, and moves the bar tick to an accumulated OnUpdate clock so a frame costs no repeated client clock call. The offline suite is refreshed for these contracts: **59 steps / 0 failed**.

### 🔒 Secret-Value Access Hardening (v2.2.0)

- 🛡️ **Probe before compare:** `compat.lua`, `hunter_ui.lua`, `enemy_swing.lua`, `forever_guide.lua`, `swing_source.lua`, `LibGlobalCooldown.lua` and the vendored swing library now call `canaccessvalue`/`canaccessallvalues` before touching a client-provided cooldown, cast, attack-speed, target-name/GUID or cast-bar key. A restricted read is treated as unknown instead of reaching arithmetic or a timer.
- 🧱 **Nil-safe seams:** missing profile rows, hand tables, aura rows, option entries and guide inputs now return early across `aura_icons.lua`, `bars.lua`, `designmode.lua`, `diag.lua`, `main.lua`, `option_tables.lua`, `power_bar.lua`, the practice modules, `rogue_guide.lua`, `weave_range.lua` and `widgets.lua`.
- 🎨 **Aura row strata:** native `AuraContainer` rows no longer set an explicit frame strata at creation; the client default applies.

### ⏱️ Bar Tick & UI Polish (v2.2.0)

- **Live tick clock:** `bars.lua` reads the client clock exactly once per tick and shares that reading with the no-cycle early-return paint and the timer text. The OnUpdate delta is deliberately **not** accumulated: a bar's OnUpdate pauses while its frame is hidden, so a cached clock resumes stale and the fill sits at zero until it replays the hidden gap. The install boundary in `main.lua` adapts the client's `(frame, elapsed)` call to the hand handler's `elapsed` argument. The fill-last and resize-repaint guarantees are unchanged.
- **Design-mode reset:** the bar reset seam now targets the class defaults row and hands the live row to `LibWindow.RestorePosition`; option generation tolerates an unknown hand row and a nil order offset.

### 🧪 Test Suite (v2.2.0)

- **Client probes in every sandbox:** 27 suites now provide `canaccessvalue`/`canaccessallvalues` (secret-aware where restricted values are modelled), the strict `forever_guide.lua` allow-list includes `tonumber` and both probes, the `bars.lua` tick pins the cold/warm cached-clock reads, and the `aura_icons.lua`, `designmode.lua` and `main.lua` pins follow the current contracts.

## 🚀 What's New in v2.1.9

> [!IMPORTANT]
> **<span style="color:#FFD700">WoW Forever (Camelot 1.60.1)</span> Aura Row, Hunter Cast Bar & Range Bar Overhaul!** SwedgeTimer v2.1.9 fixes the WoW Forever Aura Icon Rows above the Hunter Auto Shot cast bar (`st.hunter_ui` resolution + 29 px ranged clearance), restores missing cooldown/proc buff icons above the debuff row (`Blizzard_AuraContainer` pre-anchoring + `SetAuraProcessingPolicy(0)` + `UpdateAllAuras` + full Classic/Forever multi-rank proc/trinket/racial IDs), fixes the horizontal distance range bar's `1`/`0` boolean normalization and secret-geometry guards, and delivers enterprise-grade visual polish (crisp outlined typography, `<4s` low-duration red color curve, reverse buff cooldown sweeps, and styled debuff duration bars).

### ✨ WoW Forever Aura Icons & Range Bar Polish (v2.1.9)

- 🏹 **Hunter Cast Bar Clearance Fixed**: `topmost_hunter_widget` now reads the live `st.hunter_ui` namespace (`cast_frame`, `rapid_fire_bar`, `target_warning`), re-anchors on the same frame via `hunter_ui.update`, and reserves `29 px` above the ranged bar (`17 px` cast bar + `12 px` clearance) so the `27 px` debuff icons and their `5 px` duration bars clear `Auto Shot` cleanly by `7 px` without overlapping or jumping.
- 🔥 **Buff Cooldown & Proc Icons Above Debuffs**: Pre-anchors native `AuraContainer` frames before `SetUnit`/`AddAuraGroup` so `IsVisible()` is true when `ShouldRegisterForDynamicEvents()` registers `UNIT_AURA`, triggers `SetAuraProcessingPolicy(0)` + `UpdateAllAuras()` on anchor and `UNIT_TARGET`, and adds full multi-rank buff/proc/trinket/racial spell IDs (Rapid Killing `35098`/`35099`, The Beast Within `34471`, Deterrence `19263`, Furious Howl, Expose Weakness, Master Tactician, Flurry ranks, Enrage ranks, Vengeance ranks, Troll Berserking ranged `26635` / melee `20554`, Crusader, Mongoose, Earthstrike, Swarmguard, Kiss of the Spider, Slayer's Crest, Jom Gabbar, ZHC, Diamond Flask).
- 📏 **Horizontal Distance Range Bar Fixed**: `hunter_ui.spell_range_band()` and `weave_range.spell_band()` now normalize `1`/`0` returns from `compat.IsSpellInRange` alongside `true`/`false`, probe numeric spell IDs (`2974`, `2973`, `75`), arm `C_SwingTimer.EnableRangeCheck` on init, add a `ClosestUnitPosition(UnitCreatureID("target"))` continuous yard fallback on Forever, and guard all layout/anchor geometry reads against secret values.
- 🎨 **Enterprise-Grade Visuals**: Crisp `OUTLINE` typography with drop shadows on aura countdowns, gold stack counts, and range labels; secret-safe `<4.0s` red `C_CurveUtil` countdown warning curve; reverse `CooldownFrameTemplate` radial sweeps on buff icons; dark-framed crimson debuff duration bars.

### ✨ WoW Forever Display, Range & Power Fixes (v2.1.8)

- 🏹 **Auto Shot Display Recovery**: The visibility heartbeat no longer dies with the range poll (bars keep showing and hiding), a ranged swing START/UPDATE or a completed shot opens the ranged bar in the same event, a secret/malformed swing duration is recovered from your equipped speed instead of silently skipping the shot, and a restricted weapon-stat read no longer marks the hand as "no weapon" — the persistent "Auto Shot not displayed" variant. Auto Shot auto-repeat is probed with the client's numeric id (`75`) so the ranged activity backstop works.
- 📏 **Range Bar Shows The Real Band**: `UnitDistanceSquared` only answers for units in your group and not in instances, so an enemy target reads unknown on Forever. The bar now falls back to the client's own exact swing-range check (`C_SwingTimer.IsTargetWithinSwingRange`) and paints `<=5 yd MELEE`, `5-35 yd IN RANGE` or `>35 yd OUT` — never an invented yard count — and only shows the explicit `--` face when both exact tiers are silent (no target or a non-attackable target still hides it). Its driver no longer permanently quarantines itself, and its initialization is guarded with a world-entry retry.
- 🔋 **Secret Power Bar**: A restricted (secret) power reading is passed raw through a real StatusBar for the fill and through `FontString:SetText` for the number (the client's sanctioned secret sinks), so the bar stays visible and shows the value instead of hiding or printing `?`.
- ⏱️ **Bar Text & Tick**: Attack-speed and timer text no longer show eight weapon speeds a tenth low (`1.4`/`1.9`/`2.3`/`2.4`/`2.8`/`2.9`/`3.3`/`3.8`), and each bar tick now reads the clock once, caches the spark decoration and writes the fill once.

### 🔒 Secret-Value Hardening (WoW Forever, v2.1.8)

- 🧠 **Restricted reads are UNKNOWN, never guessed**: A restricted cooldown, power, target-aura or target-health read no longer becomes `0`/"ready"/"absent"/`100 %`; the class gathers mark the tick unknown and the Forever guide withholds advice instead of cueing Judgement/Arcane/Rend/Rip/Rake/Flame Shock/Enrages on hidden data. The same pass fixed a latent paladin mana-compare crash.
- 🛡️ **Target-of-target warning still renders**: A restricted `UnitIsUnit` result is passed through the client's sanctioned `SetAlphaFromBoolean` sink as a secret boolean instead of being compared or guessed; the readable path is unchanged.
- 🔋 **HUD trinkets stay visible**: A restricted item-cooldown read keeps an equipped on-use trinket on screen with the existing grey unknown face (no swipe or countdown) instead of hiding it; a readable passive still hides.
- 🏹 **Hunter identity and auras**: Target identity uses the secret-safe `api.UnitGUID` (no raw comparison), the three aura scans no longer truncate on a restricted row (Rapid Fire, Frenzy and the aspect icon keep working), and an unknown `UnitCreatureType` is not treated as "not undead".
- 🧩 **Compat hardening**: The classic `UnitAura` branch now carries the `C_Secrets` per-index precheck and a `pcall`; combat-rating reads are guarded; new restricted-aware helpers (`api.get_cooldown_remaining`, `api.spell_aura_may_be_secret`, `api.power_may_be_secret`, `api.health_max_may_be_secret`, a fourth `restricted` return on `api.GetInventoryItemCooldown`) leave existing contracts unchanged.

### 🌟 Release Highlights (v2.1.7)

- ⚔️ **Complete WoW Forever 1.60.1 Rotation Engines (<span style="color:#FFD700">6 Classes / 16 Specs</span>)**:
  - **<span style="color:#F58CBA">Paladin</span>**: Retribution (Holy Strike weaving, HoW execute, Seal cycling), Holy Shock burst, and Protection Tank (Holy Shield, Seal of Fury, Righteous Fury).
  - **<span style="color:#C79C6E">Warrior</span>**: Arms (Bloodthrill Overpower procs, Slam weaving), Fury (Bloodthrill Overpower within 5–73 rage), and Protection Tank (Shield Wall <span style="color:#FF4500"><= 35% HP</span>, Last Stand <span style="color:#FF4500"><= 40% HP</span>, Shield Slam, Revenge).
  - **<span style="color:#ABD473">Hunter</span>**: Melee Survival (gated strictly on `Strider Kick`), Ranged Turret/Weaving (with 4.0s Sniper Shot & Auto Shot clip protection), and Summon Hawk.
  - **<span style="color:#FFF569">Rogue</span>**: Mutilate, Combat Daggers (Backstab), Subtlety (Hemo), and Combat Swords (Sinister Strike) with <span style="color:#00FF00">100% Slice & Dice uptime</span>, Venom, TTD-based Rupture, and reactive Riposte parry procs.
  - **<span style="color:#FF7D0A">Druid</span>**: Feral Bear Tank (Barkskin <span style="color:#FF4500"><= 40% HP</span>, Frenzied Regen <span style="color:#FF4500"><= 30% HP</span>, Primal Bite, Lacerate 5-stacks) and Feral Cat DPS (Stealth Ravage, Clearcasting Shred, 5-CP Rip, Ferocious Bite).
  - **<span style="color:#0070DE">Shaman</span>**: Authentic 2H Enhancement rotation (Flame Shock DOT upkeep, Stormstrike, 5-stack Maelstrom Weapon instant Lightning Bolt, Earth Shock, Fire Nova).
- 🛡️ **Full Tanking Engines across <span style="color:#FFD700">WoW Forever</span> & <span style="color:#00BFFF">TBC Anniversary</span>**: Dedicated **<span style="color:#F58CBA">Protection Paladin</span>** (Holy Shield, Avenger's Shield, Righteous Fury), **<span style="color:#C79C6E">Protection Warrior</span>** (Shield Wall <span style="color:#FF4500"><= 35% HP</span>, Last Stand <span style="color:#FF4500"><= 40% HP</span>, Shield Block, Shield Slam, Revenge, Devastate vs Sunder ladder), and **<span style="color:#FF7D0A">Feral Bear Druid</span>** (Frenzied Regen <span style="color:#FF4500"><= 40% HP</span>, Maul queue RIDE, Mangle, Faerie Fire, Demo Roar, Lacerate 5-stack, Swipe filler) engines with auto-shield/form detection, emergency health thresholds, and real-time leveling fallbacks.
- ⚡ **Performance & Responsiveness Overhaul**:
  - **Instant Input Bridging**: Real-time combat states (combo points, energy/rage, bleeds, buffs, and cooldowns) translate seamlessly into <span style="color:#00FF00">zero-latency</span> rotation cues.
  - **High-Speed Cooldown Caching**: Cooldown and spell-known queries run through an optimized high-frequency cache, <span style="color:#00FF00">dramatically reducing CPU overhead</span> during intense 20Hz combat frames.
  - **Global Cooldown Snapshotting**: Replaced redundant spell queries with GCD state snapshotting for <span style="color:#00FF00">jitter-free</span> guide animations.
- 🎯 **Smarter Next-Action Guide & Cooldown HUD**:
  - Live HUD slot providers for all 6 classes: active cooldown remaining, GCD swipes, resource/mana <span style="color:#1E90FF">blue tint</span>, out-of-range <span style="color:#FF4500">red tint</span>, and <span style="color:#FFD700">proc/execute glows</span>.
  - Dynamic multi-rank spellbook validation on <span style="color:#FFD700">WoW Forever</span> ensures unlearned ability icons and prompts never clutter your screen while leveling.
  - Fine-tuned spell matching: corrected Flame Shock rank scaling, disambiguated Hunter Aspect of the Hawk from Summon Hawk, and aligned all action prompts with HUD icon slots.
- 📈 **Dynamic Leveling Progression (Level 1–70)**: Spells unlock dynamically in both the HUD and Next-Action Guide as you train them—**<span style="color:#00FF00">no /reload required</span>**! Clean leveling fallbacks ensure you never stall on unlearned talents.
- ⏱️ **Native Hardware-Accurate Timing**: Seamless integration with WoW Forever's native `C_SwingTimer` API and `PLAYER_SWING` events for <span style="color:#00FF00">jitter-free weapon timing</span>.

### 🛠️ WoW Forever Runtime Hardening (v2.1.7)

- 🧾 **Verified Spell Rank Tables**: `FG.SPELLS` now carries the Wowhead Forever ladder set for the 81 tracked spells, replacing the earlier mixed classic/Forever ids: 80 ladders are verified against the Forever DB, with Faerie Fire (Feral) the one documented exception below. Wrong ids were removed: Sniper Shot `14266` (Raptor Strike R8) → `1310687`, Demoralizing Shout `11549`/`11550`/`11551` (Battle Shout) → `11554`/`11555`/`11556`, Searing Totem `10587` (Magma Totem) removed, Claw `9823`/`9827` (Pounce) → `5201`/`9849`/`9850`, Seal of the Crusader `21183` (Judgement debuff) removed with `21082` added, Consecration `20142` → `20116`, and Bloodthrill `1282733` (the APL's Overpower proc aura) → `1289682`.
- ➕ **Missing Ranks Restored**: Slam R1 `1240193`, Mutilate's eight-id ladder, Backstab R9 `25300`, Lacerate R1–R5 plus alternate R4 `1299332`, Primal Bite R1–R4, Ferocious Bite R1 `1328618` and R6 `31018`, Fire Nova `408341`–`408345`, Holy Shield's single rank, the full Seal of Fury ladder, Righteous Fury `407627`, the Exorcism/Serpent Sting/Lightning Bolt alternate families, and the Maul/Shred/Swipe rank fills. Faerie Fire (Feral) now carries the operator-ordered union `{16857, 17390, 17391, 17392, 784, 1070, 13424, 13752}`: the first four are the classic fallback and `784`/`1070`/`13424`/`13752` are **unverified Forever candidates** (the spell is not present in Wowhead's Forever DB), kept by operator order — the one line not verified against Forever data.
- 🧿 **Restricted Aura Reads Fixed**: `C_Secrets.ShouldUnitAuraIndexBeSecret` is probed before each indexed `C_UnitAuras.GetAuraDataByIndex` read, and the read is `pcall`-wrapped — a secret aura row now reports absent instead of raising the BugSack error `GetAuraDataByIndex(): Auras cannot be accessed when secret...`.
- ⏳ **Restricted Cooldown Reads Handled Honestly**: A readable cooldown source is no longer discarded because another source returned secret values, and `C_Spell.GetSpellCooldownDuration` is used as a fallback when `GetSpellCooldown` is restricted. `api.GetSpellCooldown` gains a fifth `restricted` return so consumers can tell hidden timing apart from "ready"; the classic four-value shape is unchanged on Era / TBC / Wrath.
- 🚫 **No Invented Timing Cues**: The Next-Action Guide marks a tick `inputs_unknown` and withholds the suggestion when the client hides cooldown timing, and the Cooldown HUD renders a restricted read as unknown — greyed, with no swipe or countdown text — instead of ready.
- 🖼️ **Forever HUD Wiring Fixed**: Forever icons, per-icon option toggles and the HUD templates all read and write `hud_forever_show_<key>` (legacy `hud_show_*` unchanged elsewhere), so legacy `false` defaults no longer hide Holy Strike, Holy Shield, Lightning Shield, Searing Totem or Claw. A nil Forever provider answer no longer falls through to the class provider, and `/st diag`'s Forever spell-registry check now runs only on Forever clients. The HUD event frame no longer registers `COMBAT_LOG_EVENT_UNFILTERED` on Mainline-code clients (tainted register raises `ADDON_ACTION_FORBIDDEN`, uncatchable by `pcall`); classic registration unchanged.
- 🔌 **Class-Side Forever Wiring**: Rogue threads FG's `inputs_unknown` into the guide's unknown state, publishes `mh_is_dagger` from the existing dagger helper, and uses `Venom` for Forever labels/probes (TBC/Wrath keep `Envenom`). Druid publishes tri-state `prowl_active` from the merged player-buff walk (`nil` = unknown on a secret-regime miss), hunter reads `mana_frac`, and paladin passes FG's `sor`/`WAIT` through unmapped (the legacy `sob`/`HOLD` remap stays on other families).
- 🧹 **Guide Output No Longer Stale**: `action`, `spell_name`, `judge_call` and `rotation_key` are cleared every tick, so HOLD / POOL / WAIT branches and new fights no longer re-display the previous tick's action or latch the Judgement icon.
- 🧭 **Guide Leveling, Stalls, Swipes and Shield Wiring**: paladin leveling requires its Seal known else HOLD/WAIT; hunter leveling and druid caster hold WAIT instead of blanking; Forever guide slots carry cooldown keys where a matching input exists; warrior Thunder Clap / Cleave stay marked filed-skeleton without a Forever target-count producer; shaman Water Shield uses its own Forever-gated due flag.
- 🗡️ **Rogue Finisher Uses Venom**: The WoW Forever rogue finisher now uses the client's `Venom` name (id `1310703`) and is driven by `venom_ready`, `venom_buff_active` and `cp >= 3`; the internal action key stays `envenom`, so nothing else moves.

*All WoW Forever behaviour in this section is verified offline by the unit suites; in-client confirmation on the Forever client is still pending.*

---

## 🎮 Supported Clients

| Client / Server | Interface | Swing Timer Engine | Special Features |
| :--- | :--- | :--- | :--- |
| **<span style="color:#FFD700">WoW Forever</span>** (Camelot) | `16001` | **<span style="color:#00FF00">● LIVE</span>** | Native swing engine, full 6-class Forever APL rotations, 2H Shaman, Melee Hunter, Tank rotations & leveling fallbacks |
| **<span style="color:#FFD700">Classic Era & SoD</span>** | `11509` | **<span style="color:#00FF00">● LIVE</span>** | Classic combat engine, Season of Discovery runes, Exodin & Shockadin builds, Hunter melee stack |
| **<span style="color:#FFD700">TBC Anniversary</span>** | `20506` | **<span style="color:#00FF00">● LIVE</span>** | Dedicated Paladin Seal-Twisting window, Hunter Auto Shot clipping bar, Windfury sync, Protection Paladin/Warrior & Feral Bear tank engines |
| **<span style="color:#FFD700">WotLK Titanforge</span>** | `38002` | **<span style="color:#00FF00">● LIVE</span>** | High-precision FCFS next-action rotation, Wrath utility band, rank consolidation |
| **<span style="color:#AAAAAA">Retail / Midnight</span>** | `12.1.x` | **<span style="color:#888888">○ UI Only</span>** | Cooldown HUD, layout designer, range checking & options active (swing bars static by design) |
| **<span style="color:#AAAAAA">Cataclysm / Mists</span>** | `40402` / `50500` | **<span style="color:#888888">○ UI Only</span>** | Cooldown HUD, design mode & options interface active |

> [!TIP]
> Playing on **WoW Forever**? SwedgeTimer connects directly to the client's native `C_SwingTimer` engine and `PLAYER_SWING` events for frame-accurate timing without combat log delay!

---

## ✨ Features You'll Love

### ⏱️ Cycle-Accurate Swing & Shot Timers

- **Main Hand & Off Hand**: Watch your weapon attacks glide across crisp, responsive bars with custom animated leading sparks and completion pulse flashes.
- **Ranged & Auto Shot**: Hunters see the exact windup, release, and red clipping zone so you never clip an Auto Shot again!
- **Dynamic Hand Hiding**: Off Hand and Ranged bars only show when you actually attack or arm a shot, keeping your screen uncluttered.
- **Hunter Melee Stack**: Automatically pins your thin melee bars directly underneath your ranged bar at identical width.

> [!TIP]
> **Hunter Auto Shot Mastery**: The <span style="color:#FF4500">solid red endzone</span> indicates the unshootable clip window. Wait for the <span style="color:#00FF00">green release phase</span> before moving or queueing spells to maximize your DPS.

### 🔋 Universal Primary Resource Bar

- Seamlessly tracks **Mana**, **Rage**, **Energy**, or **Focus** right below your weapon swings.
- Built-in energy tick tracking for **<span style="color:#FFF569">Rogues</span>** and **<span style="color:#FF7D0A">Druids</span>** in Cat Form so you can time your bursts with incoming energy ticks.

### 🎯 Intelligent Next-Action Rotation Guide

- Real-time icon prompt showing you the exact best spell to cast next, calibrated directly from official simulation priority models.
- **Dynamic Leveling Progression**: Works seamlessly from **Level 1 to 70**! As you learn new spells and talents, SwedgeTimer automatically detects them and smoothly updates your rotation in real time without needing a `/reload`.
- **Leveling Fallbacks**: Missing late-game talents? SwedgeTimer automatically falls back to baseline leveling abilities (Rend, Heroic Strike, Claw, Sinister Strike, baseline Holy Strike, totems, and shocks).

> [!NOTE]
> **<span style="color:#00FF00">Zero Reloads Needed</span>**: Visiting a class trainer? As soon as you purchase a new spell rank or allocate talent points, SwedgeTimer immediately recognizes it and updates your rotation on the very next frame tick!

### 🛡️ Full Tanking Support on <span style="color:#FFD700">WoW Forever</span> & <span style="color:#00BFFF">TBC Anniversary</span>

- Dedicated **<span style="color:#F58CBA">Protection Paladin</span>**, **<span style="color:#C79C6E">Protection Warrior</span>**, and **<span style="color:#FF7D0A">Feral Bear Tank</span>** rotation modes with defensive health triggers (Shield Wall, Last Stand, Barkskin, Frenzied Regeneration) and threat builders (Shield Slam, Primal Bite, Lacerate, Revenge).

> [!IMPORTANT]
> **Auto-Shield & Form Detection**: Equipping a shield or shifting into Bear Form automatically switches the guide to your class's dedicated tanking priority list without requiring manual menu toggles.

### 🥋 In-Game Practice Gym (`/st practice`)

- Step into the practice gym to rehearse your rotation, swing timing, and seal twists offline without wasting raid buffs or consumables!
- Features interactive scrolling timelines, mastery tiers (<span style="color:#CD7F32">Bronze</span> → <span style="color:#C0C0C0">Silver</span> → <span style="color:#FFD700">Gold</span> → <span style="color:#00FFFF">Platinum</span>), and graded performance scores!

---

## ⚔️ Class Rotations & Specializations

### 🛡️ **<span style="color:#F58CBA">Paladin</span>**

- **Retribution**: Immediate `Judgement` on cooldown → `Hammer of Wrath` execute → `Holy Strike` weaving (filling empty globals between judgements) → `Seal of Command` / `Seal of Righteousness` upkeep → `Consecration` & `Exorcism` mana-managed fillers.
- **Holy Shock (Shockadin)**: `Judgement` → `Consecration` → Seal upkeep → `Holy Strike` → `Divine Favor` + `Holy Shock` burst → `Hammer of Wrath` → `Exorcism`.
- **Protection (Tank)**: `Righteous Fury` upkeep → `Judgement` → `Seal of Fury` (or `Seal of Righteousness`) → `Consecration` → `Holy Shock` → `Holy Shield` → `Holy Strike` → `Exorcism`.
- **Leveling**: Smooth Level 1–60 progression using Seal of Righteousness, Judgement, baseline Holy Strike (Level 6), Consecration (Level 20), and Exorcism (Level 24).
- **TBC Seal-Twisting**: Dedicated seal-twist window band with live attempt and success detection!

> [!TIP]
> **Holy Strike Weaving**: Paladins on WoW Forever learn Holy Strike at level 6. SwedgeTimer prompts Holy Strike to fill empty global cooldowns while Judgement is on cooldown, delivering maximum DPS without clipping swing timers.

### ⚔️ **<span style="color:#C79C6E">Warrior</span>**

- **Arms**: `Overpower` on Bloodthrill procs and dodges (only 5 rage!) → `Mortal Strike` → `Whirlwind` → `Slam` → `Rend` upkeep → `Execute` burn phase → `Cleave` (multi-target) & `Heroic Strike` rage dump (90+ rage).
- **Fury**: `Whirlwind` on AoE → `Overpower` weaving on Bloodthrill procs (5–73 rage) → `Execute` phase → `Bloodthirst` → `Heroic Strike` queueing → `Rend` weaving & `Hamstring` utility.
- **Protection (Tank)**: Emergency defensives (`Shield Wall` at <= 35% HP, `Last Stand` at <= 40% HP) → `Shield Block` uptime → `Shield Slam` → Fury-Prot `Bloodthirst` & Arms-Prot `Mortal Strike` → `Revenge` procs → `Sunder Armor` 5-stack upkeep → `Thunder Clap` & `Demoralizing Shout` → `Cleave` / `Heroic Strike`.
- **Leveling**: High-priority Overpower procs, Execute, Rend bleed upkeep, Sunder Armor, and Heroic Strike rage dumping.

### 🏹 **<span style="color:#ABD473">Hunter</span>**

- **Melee Survival**: Gated on the **`Strider Kick`** talent → `Raptor Strike` → `Hunter's Mark` → `Mongoose Bite` (on dodge) → `Strider Kick` → `Immolation Trap` → `Summon Hawk` → `Wing Clip` → gap closers while moving into melee.
- **Ranged Weave & Turret**: Auto Shot clipping management → `Hunter's Mark` → `Serpent Sting` → `Arcane Shot` → `Multi-Shot` → `Aimed Shot` → **`Sniper Shot`** (4s heavy cast) → **`Summon Hawk`**. In melee range, immediately weaves `Raptor Strike`, `Strider Kick`, `Mongoose Bite`, and `Immolation Trap`.
- **Leveling**: Adaptable Level 1–19 baseline rotation smoothly evolving from Raptor Strike and Serpent Sting up to full ranged turret and trap utility.

> [!NOTE]
> **Survival Melee Mode**: The melee rotation is strictly gated on having learned the **Strider Kick** talent (or manually enabling it in `/st`), ensuring ranged hunters are never erroneously prompted for melee abilities just for standing close.

### 🗡️ **<span style="color:#FFF569">Rogue</span>**

- **Mutilate (Assassination / Combat)**: 2-Combo-Point builder `Mutilate` → `Slice and Dice` 100% uptime → `Venom` / `Rupture` → `Eviscerate` at 4–5 Combo Points.
- **Combat Daggers**: Positional `Backstab` builder → `Slice and Dice` → `Rupture` / `Eviscerate`.
- **Subtlety**: Low-cost `Hemorrhage` builder → `Slice and Dice` → `Rupture` / `Eviscerate`.
- **Combat Swords / Maces**: `Sinister Strike` builder → `Slice and Dice` → `Rupture` / `Eviscerate`.
- **Defense & Utility**: `Riposte` on parry (only 10 energy!) and `Expose Armor` maintenance.
- **Leveling**: Reliable Sinister Strike, Slice and Dice, Eviscerate, and Riposte progression.

### 🐾 **<span style="color:#FF7D0A">Druid</span>**

- **Feral Bear (Tank)**: Emergency defensives (`Barkskin` at <= 40% HP, `Frenzied Regeneration` at <= 35% HP) → `Enrage` rage generation → `Faerie Fire (Feral)` → `Demoralizing Roar` → **`Primal Bite`** on cooldown → **`Lacerate`** 5-stack building and upkeep → `Swipe` on AoE → `Maul` queueing.
- **Feral Cat (DPS)**: Prowl `Ravage` opener → `Faerie Fire (Feral)` → Clearcasting proc `Shred` priority → 5-Combo-Point `Rip` bleed upkeep → `Ferocious Bite` finisher → `Tiger's Fury` damage buff → `Rake` bleed upkeep → `Shred` (behind target) or `Claw` builder.
- **Leveling**: Seamless shapeshifting progression covering Caster Wrath/Moonfire (Levels 1–9), Bear Maul/Enrage (Level 10+), and Cat Claw/Rip (Level 20+).

### ⚡ **<span style="color:#0070DE">Shaman</span>**

- **2H Enhancement**: Built purely for 2-Handed weapon combat (**no Dual Wield, no Lava Lash**) → `Flame Shock` debuff upkeep → `Stormstrike` on cooldown → 5-stack Maelstrom Weapon instant **`Lightning Bolt`** weave → `Earth Shock` → `Fire Nova` → Totem upkeep (Strength of Earth, Windfury/Grace of Air, Mana Spring, Searing Totem) → `Water Shield` / `Lightning Shield`.
- **Leveling**: Rockbiter / Flametongue weapon imbues → Lightning Shield upkeep → Flame Shock dot → Earth Shock burst → Searing Totem → Lightning Bolt finisher.

> [!IMPORTANT]
> **Verified 2H Enhancement Mechanics**: On WoW Forever, Enhancement Shamans wield powerful Two-Handed weapons (**no Dual Wield, no Lava Lash**). SwedgeTimer models the exact 2H rotation with 5-stack Maelstrom Weapon instant Lightning Bolt weaves and totem maintenance.

---

## ⌨️ Slash Commands

| Command | Description |
| :--- | :--- |
| <span style="color:#FFD700">`/st`</span> | Opens the main configuration panel (bars, colors, sizing, fonts, layout). |
| <span style="color:#FFD700">`/st design`</span> | Toggles **Design Mode** — click and drag bars, HUD, and text anywhere on your screen! |
| <span style="color:#FFD700">`/st practice`</span> | Opens the **Practice Gym** to train your rotation on an interactive timeline. |
| <span style="color:#FFD700">`/st diag`</span> | Runs a live **Diagnostic Audit** in chat, verifying spellbook detection and engine health. |

> [!TIP]
> Type `/st design` to unlock all frames, bars, and icons for easy drag-and-drop repositioning anywhere on your screen! Type `/st design` again when finished to lock everything in place.

---

## 📦 Installation

### Option 1: CurseForge App (Recommended)

1. Open the **CurseForge App**.
2. Search for [**<span style="color:#FF8000">SwedgeTimer</span>**](https://www.curseforge.com).
3. Click **Install**. The app will handle automatic updates!

### Option 2: Manual Install

1. Download the latest `.zip` release.
2. Extract the `SwedgeTimer` folder into your World of Warcraft AddOns directory:
   - **WoW Forever**: `World of Warcraft/Interface/AddOns/SwedgeTimer`
   - **Classic Era / SoD**: `World of Warcraft/_classic_era_/Interface/AddOns/SwedgeTimer`
   - **TBC Anniversary**: `World of Warcraft/_classic_/Interface/AddOns/SwedgeTimer`
   - **WotLK Titanforge**: `World of Warcraft/_classic_/Interface/AddOns/SwedgeTimer`
   - **Retail**: `World of Warcraft/_retail_/Interface/AddOns/SwedgeTimer`
3. Launch World of Warcraft. The addon ships one `SwedgeTimer.toc` that advertises every supported client, so there is no flavor file to pick.

> [!NOTE]
> **One TOC for every client (v2.1.8):** the old per-flavor `.toc` files are gone. `SwedgeTimer.toc` lists `## Interface: 11509, 20506, 38002, 40402, 50500, 120100, 120105, 16001`; the client picks its engine at runtime, and the classic swing library is gated off on Forever/Retail/Cata/Mists by `swing_lib_gate.lua` (so it is listed once, never duplicated per flavor).

---

## 🎨 Themes & Customization

Pick from ready-made visual presets under `/st` → **Bar Appearance**:

- **Midnight Velvet**: Modern dark aesthetic with refined contrasting borders.
- **Clean Glassmorphic**: Frosted glass translucent design with luminous accent lines.
- **Minimalist / ElvUI**: Ultra-thin flat borders tailored for minimalist UI suites.
- **Classic Retro**: Nostalgic Blizzard classic interface styling.

*All swing bars automatically inherit your character's official raid class color by default!*

---

## 📜 Credits & License

- **Paladin Seal-Twisting Research**: Credit to `forktale` ([SwedgeTimer TBC Anniversary Update](https://www.curseforge.com/wow/addons/swedgetimer-tbc-anniversary-update)).
- **Simulation Models**: Action Priority Lists and rotations powered by the [wowsims](https://github.com/wowsims) project ([<span style="color:#1E90FF">wowsims.com</span>](https://www.wowsims.com)).
- **License**: GNU General Public License v3.0 — see [LICENSE](LICENSE).
