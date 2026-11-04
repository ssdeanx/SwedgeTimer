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

## 🚀 What's New in v2.1.5

> [!IMPORTANT]
> **WoW Forever (Camelot 1.60.1) Launch Ready!** SwedgeTimer v2.1.5 delivers full, enterprise-grade rotations for all 6 melee classes calibrated directly against official simulation priority models, along with full tanking engines and real-time leveling progression.

### 🌟 Release Highlights

- ⚔️ **Complete WoW Forever APL Rotations**:
  - **<span style="color:#F58CBA">Paladin</span>**: Retribution (Holy Strike weaving, HoW execute, Seal cycling), Holy Shock burst, and Protection Tank (Holy Shield, Seal of Fury, Righteous Fury).
  - **<span style="color:#C79C6E">Warrior</span>**: Arms (Bloodthrill Overpower procs, Slam weaving), Fury (Bloodthrill Overpower within 5–73 rage), and Protection Tank (Shield Wall $\le 35\%$, Last Stand $\le 40\%$, Shield Slam, Revenge).
  - **<span style="color:#ABD473">Hunter</span>**: Melee Survival (gated strictly on `Strider Kick`), Ranged Turret/Weaving (with 4.0s Sniper Shot & Auto Shot clip protection), and Summon Hawk.
  - **<span style="color:#FFF569">Rogue</span>**: Mutilate, Combat Daggers (Backstab), Subtlety (Hemo), and Combat Swords (Sinister Strike) with 100% Slice & Dice uptime, Envenom, TTD-based Rupture, and reactive Riposte parry procs.
  - **<span style="color:#FF7D0A">Druid</span>**: Feral Bear Tank (Barkskin $\le 40\%$, Frenzied Regen $\le 30\%$, Primal Bite, Lacerate 5-stacks) and Feral Cat DPS (Stealth Ravage, Clearcasting Shred, 5-CP Rip, Ferocious Bite).
  - **<span style="color:#0070DE">Shaman</span>**: Authentic 2H Enhancement rotation (Flame Shock, Stormstrike, 5-stack Maelstrom Weapon instant Lightning Bolt, Earth Shock, Fire Nova).
- 🛡️ **Full Tanking Engines**: Dedicated Protection Paladin, Protection Warrior, and Feral Bear engines with auto-shield detection and health-threshold defensives.
- 📈 **Dynamic Leveling Progression (Level 1–60)**: Spells unlock dynamically in the guide as you train them—**no `/reload` required**! Clean leveling fallbacks ensure you never stall on unlearned talents.
- ⏱️ **Native Hardware-Accurate Timing**: Seamless integration with WoW Forever's native `C_SwingTimer` API and `PLAYER_SWING` events for jitter-free weapon timing.

---

## 🎮 Supported Clients

| Client / Server | Interface | Swing Timer Engine | Special Features |
| :--- | :--- | :--- | :--- |
| **<span style="color:#FFD700">WoW Forever</span>** (Camelot) | `16001` | **<span style="color:#00FF00">● LIVE</span>** | Native swing engine, full 6-class Forever APL rotations, 2H Shaman, Melee Hunter, Tank rotations & leveling fallbacks |
| **<span style="color:#FFD700">Classic Era & SoD</span>** | `11509` | **<span style="color:#00FF00">● LIVE</span>** | Classic combat engine, Season of Discovery runes, Exodin & Shockadin builds, Hunter melee stack |
| **<span style="color:#FFD700">TBC Anniversary</span>** | `20506` | **<span style="color:#00FF00">● LIVE</span>** | Dedicated Paladin Seal-Twisting window, Hunter Auto Shot clipping bar, Windfury sync |
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
> **Hunter Auto Shot Mastery**: The solid red endzone indicates the unshootable clip window. Wait for the green release phase before moving or queueing spells to maximize your DPS.

### 🔋 Universal Primary Resource Bar

- Seamlessly tracks **Mana**, **Rage**, **Energy**, or **Focus** right below your weapon swings.
- Built-in energy tick tracking for **<span style="color:#FFF569">Rogues</span>** and **<span style="color:#FF7D0A">Druids</span>** in Cat Form so you can time your bursts with incoming energy ticks.

### 🎯 Intelligent Next-Action Rotation Guide

- Real-time icon prompt showing you the exact best spell to cast next, calibrated directly from official simulation priority models.
- **Dynamic Leveling Progression**: Works seamlessly from **Level 1 to 60**! As you learn new spells and talents, SwedgeTimer automatically detects them and smoothly updates your rotation in real time without needing a `/reload`.
- **Leveling Fallbacks**: Missing late-game talents? SwedgeTimer automatically falls back to baseline leveling abilities (Rend, Heroic Strike, Claw, Sinister Strike, baseline Holy Strike, totems, and shocks).

> [!NOTE]
> **Zero Reloads Needed**: Visiting a class trainer? As soon as you purchase a new spell rank or allocate talent points, SwedgeTimer immediately recognizes it and updates your rotation on the very next frame tick!

### 🛡️ Full Tanking Support on WoW Forever

- Dedicated Protection Paladin, Protection Warrior, and Feral Bear Tank rotation modes with defensive health triggers (Shield Wall, Last Stand, Barkskin, Frenzied Regeneration) and threat builders (Shield Slam, Primal Bite, Lacerate, Revenge).

> [!IMPORTANT]
> **Auto-Shield Detection**: Equipping a shield automatically switches the guide to your class's dedicated tanking priority list without requiring manual menu toggles.

### 🥋 In-Game Practice Gym (`/st practice`)

- Step into the practice gym to rehearse your rotation, swing timing, and seal twists offline without wasting raid buffs or consumables!
- Features interactive scrolling timelines, mastery tiers (<span style="color:#CD7F32">Bronze</span> $\rightarrow$ <span style="color:#C0C0C0">Silver</span> $\rightarrow$ <span style="color:#FFD700">Gold</span> $\rightarrow$ <span style="color:#00FFFF">Platinum</span>), and graded performance scores!

---

## ⚔️ Class Rotations & Specializations

### 🛡️ <span style="color:#F58CBA">Paladin</span>

- **Retribution**: Immediate `Judgement` on cooldown $\rightarrow$ `Hammer of Wrath` execute $\rightarrow$ `Holy Strike` weaving (filling empty globals between judgements) $\rightarrow$ `Seal of Command` / `Seal of Righteousness` upkeep $\rightarrow$ `Consecration` & `Exorcism` mana-managed fillers.
- **Holy Shock (Shockadin)**: `Judgement` $\rightarrow$ `Consecration` $\rightarrow$ Seal upkeep $\rightarrow$ `Holy Strike` $\rightarrow$ `Divine Favor` + `Holy Shock` burst $\rightarrow$ `Hammer of Wrath` $\rightarrow$ `Exorcism`.
- **Protection (Tank)**: `Righteous Fury` upkeep $\rightarrow$ `Judgement` $\rightarrow$ `Seal of Fury` (or `Seal of Righteousness`) $\rightarrow$ `Consecration` $\rightarrow$ `Holy Shock` $\rightarrow$ `Holy Shield` $\rightarrow$ `Holy Strike` $\rightarrow$ `Exorcism`.
- **Leveling**: Smooth Level 1–60 progression using Seal of Righteousness, Judgement, baseline Holy Strike (Level 6), Consecration (Level 20), and Exorcism (Level 24).
- **TBC Seal-Twisting**: Dedicated seal-twist window band with live attempt and success detection!

> [!TIP]
> **Holy Strike Weaving**: Paladins on WoW Forever learn Holy Strike at level 6. SwedgeTimer prompts Holy Strike to fill empty global cooldowns while Judgement is on cooldown, delivering maximum DPS without clipping swing timers.

### ⚔️ <span style="color:#C79C6E">Warrior</span>

- **Arms**: `Overpower` on Bloodthrill procs and dodges (only 5 rage!) $\rightarrow$ `Mortal Strike` $\rightarrow$ `Whirlwind` $\rightarrow$ `Slam` $\rightarrow$ `Rend` upkeep $\rightarrow$ `Execute` burn phase $\rightarrow$ `Cleave` (multi-target) & `Heroic Strike` rage dump (90+ rage).
- **Fury**: `Whirlwind` on AoE $\rightarrow$ `Overpower` weaving on Bloodthrill procs (5–73 rage) $\rightarrow$ `Execute` phase $\rightarrow$ `Bloodthirst` $\rightarrow$ `Heroic Strike` queueing $\rightarrow$ `Rend` weaving & `Hamstring` utility.
- **Protection (Tank)**: Emergency defensives (`Shield Wall` at $\le 35\%$ HP, `Last Stand` at $\le 40\%$ HP) $\rightarrow$ `Shield Block` uptime $\rightarrow$ `Shield Slam` $\rightarrow$ Fury-Prot `Bloodthirst` & Arms-Prot `Mortal Strike` $\rightarrow$ `Revenge` procs $\rightarrow$ `Sunder Armor` 5-stack upkeep $\rightarrow$ `Thunder Clap` & `Demoralizing Shout` $\rightarrow$ `Cleave` / `Heroic Strike`.
- **Leveling**: High-priority Overpower procs, Execute, Rend bleed upkeep, Sunder Armor, and Heroic Strike rage dumping.

### 🏹 <span style="color:#ABD473">Hunter</span>

- **Melee Survival**: Gated on the **`Strider Kick`** talent $\rightarrow$ `Raptor Strike` $\rightarrow$ `Hunter's Mark` $\rightarrow$ `Mongoose Bite` (on dodge) $\rightarrow$ `Strider Kick` $\rightarrow$ `Immolation Trap` $\rightarrow$ `Summon Hawk` $\rightarrow$ `Wing Clip` $\rightarrow$ gap closers while moving into melee.
- **Ranged Weave & Turret**: Auto Shot clipping management $\rightarrow$ `Hunter's Mark` $\rightarrow$ `Serpent Sting` $\rightarrow$ `Arcane Shot` $\rightarrow$ `Multi-Shot` $\rightarrow$ `Aimed Shot` $\rightarrow$ **`Sniper Shot`** (4s heavy cast) $\rightarrow$ **`Summon Hawk`**. In melee range, immediately weaves `Raptor Strike`, `Strider Kick`, `Mongoose Bite`, and `Immolation Trap`.
- **Leveling**: Adaptable Level 1–19 baseline rotation smoothly evolving from Raptor Strike and Serpent Sting up to full ranged turret and trap utility.

> [!NOTE]
> **Survival Melee Mode**: The melee rotation is strictly gated on having learned the **Strider Kick** talent (or manually enabling it in `/st`), ensuring ranged hunters are never erroneously prompted for melee abilities just for standing close.

### 🗡️ <span style="color:#FFF569">Rogue</span>

- **Mutilate (Assassination / Combat)**: 2-Combo-Point builder `Mutilate` $\rightarrow$ `Slice and Dice` 100% uptime $\rightarrow$ `Envenom` / `Rupture` $\rightarrow$ `Eviscerate` at 4–5 Combo Points.
- **Combat Daggers**: Positional `Backstab` builder $\rightarrow$ `Slice and Dice` $\rightarrow$ `Rupture` / `Eviscerate`.
- **Subtlety**: Low-cost `Hemorrhage` builder $\rightarrow$ `Slice and Dice` $\rightarrow$ `Rupture` / `Eviscerate`.
- **Combat Swords / Maces**: `Sinister Strike` builder $\rightarrow$ `Slice and Dice` $\rightarrow$ `Rupture` / `Eviscerate`.
- **Defense & Utility**: `Riposte` on parry (only 10 energy!) and `Expose Armor` maintenance.
- **Leveling**: Reliable Sinister Strike, Slice and Dice, Eviscerate, and Riposte progression.

### 🐾 <span style="color:#FF7D0A">Druid</span>

- **Feral Bear (Tank)**: Emergency defensives (`Barkskin` at $\le 40\%$ HP, `Frenzied Regeneration` at $\le 35\%$ HP) $\rightarrow$ `Enrage` rage generation $\rightarrow$ `Faerie Fire (Feral)` $\rightarrow$ `Demoralizing Roar` $\rightarrow$ **`Primal Bite`** on cooldown $\rightarrow$ **`Lacerate`** 5-stack building and upkeep $\rightarrow$ `Swipe` on AoE $\rightarrow$ `Maul` queueing.
- **Feral Cat (DPS)**: Prowl `Ravage` opener $\rightarrow$ `Faerie Fire (Feral)` $\rightarrow$ Clearcasting proc `Shred` priority $\rightarrow$ 5-Combo-Point `Rip` bleed upkeep $\rightarrow$ `Ferocious Bite` finisher $\rightarrow$ `Tiger's Fury` damage buff $\rightarrow$ `Rake` bleed upkeep $\rightarrow$ `Shred` (behind target) or `Claw` builder.
- **Leveling**: Seamless shapeshifting progression covering Caster Wrath/Moonfire (Levels 1–9), Bear Maul/Enrage (Level 10+), and Cat Claw/Rip (Level 20+).

### ⚡ <span style="color:#0070DE">Shaman</span>

- **2H Enhancement**: Built purely for 2-Handed weapon combat (**no Dual Wield, no Lava Lash**) $\rightarrow$ `Flame Shock` debuff upkeep $\rightarrow$ `Stormstrike` on cooldown $\rightarrow$ 5-stack Maelstrom Weapon instant **`Lightning Bolt`** weave $\rightarrow$ `Earth Shock` $\rightarrow$ `Fire Nova` $\rightarrow$ Totem upkeep (Strength of Earth, Windfury/Grace of Air, Mana Spring, Searing Totem) $\rightarrow$ `Water Shield` / `Lightning Shield`.
- **Leveling**: Rockbiter / Flametongue weapon imbues $\rightarrow$ Lightning Shield upkeep $\rightarrow$ Flame Shock dot $\rightarrow$ Earth Shock burst $\rightarrow$ Searing Totem $\rightarrow$ Lightning Bolt finisher.

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
3. Launch World of Warcraft. The client automatically picks the matching flavor TOC file.

> [!NOTE]
> All flavor variants are bundled into one universal download. The WoW client automatically selects the correct `.toc` file for your active game version.

---

## 🎨 Themes & Customization

Pick from ready-made visual presets under `/st` $\rightarrow$ **Bar Appearance**:

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
