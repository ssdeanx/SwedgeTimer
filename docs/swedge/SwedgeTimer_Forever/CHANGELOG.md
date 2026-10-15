# SwedgeTimer Changelog

## Version 1.9.0
**Updated by Folktale**

### Design Mode
Press **Design mode** in the settings (or type `/st design`) to arrange everything at once: drag any element into place, use the switches on the toolbar to turn elements on or off, and click an element for its key settings. Elements snap to a grid and to each other. Esc or Done finishes.

- **Simulate twists** runs a 1/2 twist rotation on screen so you can see and hear your sounds, glow and success text without a target
- Ctrl-click marks elements; drag one marked element to move them all

### Cooldown HUD (off by default)
A row of ability icons: Crusader Strike, Judgement, Consecration, Exorcism, both trinkets and Avenging Wrath, with cooldowns, mana and range warnings. Based on Nullgodx's Paladin WeakAura. Turn it on in design mode.

### Rotation Text (off by default)
A small label showing the twist rotation SwedgeTimer recommends (2/3, 2/2/5...). Turn it on in design mode.

### Other
- "Ret spec only" now reads your whole talent tree, so it works in every language and for any build
- Import / Export now carries every setting and works with strings from older versions
- Switching profiles updates the screen right away
- Nothing changes for existing profiles: your layout stays exactly as it was

---

## Version 1.8.0
**Updated by Folktale**

### New: Redesigned Settings Window

The settings menu has been rebuilt from the ground up as a custom "Radiance" window: dark glass panels over a warm glow, a searchable sidebar, tabbed pages, and modern controls (pill toggles, sliders with typed values, dropdowns with texture and font previews, colour swatches with hex entry).

- Open it with `/st` or by right-clicking the minimap button. `Esc` closes it
- Every existing setting is still here, just reorganised: General, Swing Bar (Layout / Textures & Border / Colors / Text / Seal Icons), Behaviour, Lag Compensation, Next Action Guide, Practice Mode, Twist Feedback, Import / Export and Profiles
- Search box in the sidebar finds any setting by name or description across every page
- Footer has the master on/off switch, a Ret-only switch, a "Reset page" button and a quick "Unlock bar" toggle
- Hovering an entry in the sound dropdowns previews the sound, as before
- The old AceConfig panel is still available under Interface > AddOns, or with `/st classic`
- Roboto fonts ship with the addon and are also registered with SharedMedia, so they can be used for the bar text
- Ships with painted key art and a logo (`Images/keyart.tga`, `Images/logo.tga`); replace those files to re-skin the window
- The window can be resized by dragging the grip in its bottom-right corner (double-click resets it); it opens at 60% by default

### Improvements

- Swing bar text: new "Center text" label alongside Left and Right (Swing Bar > Text > Labels)
- Next Action Guide: the "Next action:" label above the icon can be hidden (Display > Show "Next action:" label)
- Next Action Guide: choose which zone types the guide loads in (open world, dungeons, raids, battlegrounds, arenas), e.g. raids only or nothing in PvP
- Successful twist text: new "Display via" option. "Own frame" now draws above scrolling combat text addons and falls back to the standard font if the chosen font fails to load; "Scrolling combat text" hands the message to Mik's Scrolling Battle Text (or Blizzard's floating combat text) instead

### Bug Fixes

- Changing the Left/Right bar text setting no longer errors (the refresh function it called did not exist)

---

## Version 1.7.1
**Updated by Folktale**

### Bug Fixes

#### GCD Occasionally Desyncing From the Real In-Game GCD
- Fixed a rare timing issue where the GCD shown on the bar (and used by the Next Action Guide) could fall out of sync with the real in-game GCD, making the bar show "GCD free" while the game was still on cooldown — causing twists to fail even when timed correctly
- The bug was triggered by spell-queued casts: the new GCD could start milliseconds before the addon released its internal GCD lock, and the addon would then miss the new GCD entirely. This was far more likely on very low latency (under ~20ms), which is why most players never saw it
- Once triggered, it could keep recurring during tight twist rotations until you weaved another ability or briefly stopped attacking — this matches reports from players competing at high levels
- Also hardened the GCD lock so a bad cooldown reading from the game API can never leave it permanently stuck

#### Other Fixes
- The "can't twist" lag warning color now clears as soon as a twist becomes possible again, instead of occasionally lingering
- Spell cast events from other nearby players/units are now correctly ignored (previously they could subtly corrupt internal timer state used for cast interruption handling)

---

## Version 1.7.0
**Updated by Folktale**

### New: Next Action Guide

The popular "Ret Next Action Guide" WeakAura is now built directly into SwedgeTimer — no WeakAuras needed — and it works with Practice Mode!

A huge thank you to **Fonsas & Surveillant**, the original creators of the WeakAura. This feature wouldn't exist without their work.

The guide shows you what to press next:

- One icon tells you your next move: Seal of Command, Seal of Blood, twist, or Crusader Strike
- HOLD means wait — don't press anything yet
- RIDE means let your Seal of Blood auto attack happen before resealing
- A small Judgement icon appears when you should judge before resealing
- Suggests Consecration or Exorcism when you have time and mana to spare
- Shows your current rotation (e.g. "2/3") under the icon
- Works in Practice Mode too, so you can learn with it before raiding
- Find it in the settings (`/st`) under "Next Action Guide"

### Improvements

- Hover over a sound in the sound dropdowns to hear a preview
- Practice Mode: the fight timeline's colors and correct/wrong marks now always work, even with the rotation display turned off

---

## Version 1.6.3
**Updated by Folktale**

### Bug Fixes

#### Swing Timer Occasionally Showing Ready When It Shouldn't
- Fixed an issue where the swing timer would sometimes show your swing as ready when it wasn't, staying stuck until the next swing landed
- This was most noticeable when killing low HP mobs in multi-mob pulls, especially with Hand of Justice or Sword Specialization procs
- Also fixed a minor visual glitch where parry haste could briefly cause the bar to flicker on an already-completed swing

---

## Version 1.6.2
**Updated by Folktale**

### Bug Fixes

#### Seal Detection at Low Levels
- Fixed swing timer bar losing seal-specific colors and seal icon disappearing on low-level paladins (e.g., level 4 Blood Elf with Seal of Righteousness Rank 1)
- Root cause: Spell ID 21084 (the actual aura/buff ID for Seal of Righteousness Rank 1) was missing from the seal detection table in `st_data.lua`
- Added the missing spell ID to the Seal of Righteousness lookup table
- Updated the seal icon texture to use the correct Rank 1 spell ID for `GetSpellTexture()` lookup

---

## Version 1.6.1
**Updated by Folktale**

### Practice Mode Improvements

- Added spell queue window — abilities cast near the end of a GCD are now queued and fire automatically when the GCD expires
- Added gamepad/controller support for key capture and linking
- Improved keybind auto-detection for modifier keybinds (Shift-, Ctrl-, Alt- combos)
- Added ElvUI action bar support for keybind detection and bar overlay linking

---

## Version 1.6.0
**Updated by Folktale**

### New Feature: Twist Practice Mode

A fully simulated practice environment for learning and mastering seal twisting rotations. No mana costs, no real casts — just you and the swing timer.

#### Simulated Combat
- Start boss fights with simulated auto-attacks, seal casts, and ability cooldowns
- All abilities (Crusader Strike, Judgement, Consecration, Avenging Wrath) are simulated with correct cooldown timings
- Haste effects (Bloodlust, Haste Potion, DST procs) simulate realistic speed changes
- Configurable weapon speed and BL timing via `/st` settings

#### Keybind System
- Practice uses your real keybinds — auto-detected from your action bars (Bartender4, Dominos, ElvUI, default UI)
- Right-click any ability icon to manually link it to an action bar slot
- Full GCD and cooldown tracking with visual overlays on your actual action bars

#### Rotation Guide
- Center-screen rotation display shows the current optimal rotation sequence
- Automatically adapts when haste buffs change the rotation (e.g., 1/2 → 2/3 on Bloodlust)

#### Rotation Lock
- Lock practice to a specific rotation (1/2, 2/3, or 2/4) for focused practice
- When locked, weapon speed and GCD are fixed to values that produce that rotation
- All haste procs and buffs are disabled for a clean, consistent practice environment

#### Performance Timeline
- Visual timeline showing every swing, seal cast, and ability usage
- Per-swing correctness analysis: green borders for correct actions, red X for mistakes
- CS-anchored segment scoring — missed Crusader Strikes are detected even without casting one
- Rotation band tracking shows when haste changes shifted your rotation mid-fight
- Scrollable, auto-following timeline with ruler and rotation indicators

#### Stopattack Support
- Practice the stopattack twist technique (pause swing → release with seal cast)
- Correctly handles twist macros that combine startattack + seal cast

*Start with: `/st practice`*
*Settings: Practice Mode (in `/st` settings)*

### Bug Fixes

#### Practice Mode: Opener Scoring
- Fixed opener segments (before first Crusader Strike) allowing unlimited swings without penalty
- Opener is now capped at the rotation's expected pattern length — extra swings are correctly marked as CS-missed

---

## Version 1.5.3
**Updated by Folktale**

### Removed

#### Cooldowns Tracker
- Removed the cooldowns tracker feature entirely (icon frame, settings, and all related code)
- The feature was rarely used and added unnecessary complexity; dedicated cooldown addons handle this better

---

## Version 1.5.2
**Updated by Folktale**

### Bug Fixes

#### Successful Twist Text Auto-Lock
- Fixed "Successful TWIST!" text position not auto-locking when closing the settings window
- Text now automatically locks in place when you close the `/st` settings panel
- Uses proper WoW frame hook (`HookScript`) to preserve AceConfigDialog cleanup behavior

#### First Swing Twist Detection
- Fixed twist feedback not detecting successful twists on the first auto-attack swing
- Twist detection now works correctly before entering combat (e.g., opening on a mob from stealth or at range)
- Previously, the first swing after targeting a mob would not trigger twist success feedback

---

## Version 1.5.1
**Updated by Folktale**

### New Feature: Twist Feedback System

SwedgeTimer now provides real-time feedback on your seal twisting performance, helping you learn and master the twist timing.

#### Twist Attempt Detection
The addon now detects when you've correctly attempted a twist - that is, when your melee swing connects while you have both seals active (such as Seal of Command and Seal of Blood). When this happens, you can optionally receive:
- **Sound alert**: Choose from a variety of sound effects to celebrate your successful timing
- **Bar glow effect**: A customizable animated glow around the swing timer bar, with multiple styles including Pixel Glow, AutoCast Shine, Holy Nova burst, and Seal Spiral effects

#### Successful Twist Confirmation
Taking it one step further, the addon now tracks whether Seal of Command actually procced during your twist attempt. When you land a "true" successful twist (both seals active AND Command procced), a customizable "Successful TWIST!" text appears on screen. This text can be:
- Positioned anywhere on screen by dragging when unlocked
- Customized with your choice of font, size, color, and outline style
- Configured to display for a custom duration before fading out

This feedback system helps you understand not just whether you timed the twist correctly, but whether RNG blessed you with the Command proc. Over time, you'll develop a feel for your twist success rate and timing consistency.

*Settings: Twist Feedback (top of settings list)*

### Bug Fixes

#### Bar Appearance Not Saving
- Fixed an issue where bar appearance settings (colors, textures, etc.) would not persist after using `/reload`

#### Seal Icon Timer Display
- Fixed seal icon countdown timers appearing when the bar was hidden
- Timers now correctly respect the "In combat only" visibility setting

---

## Version 1.5.0
**Updated by Folktale**

### New Features

#### Minimap Button
- Added minimap button for quick access to SwedgeTimer
- Left-click to toggle the swing timer bar on/off
- Right-click to open the settings panel
- Can be hidden via "Show minimap button" toggle in settings

#### Import/Export Settings
- Export your SwedgeTimer settings to share with others
- Import settings from other players
- Option to include or exclude position settings

### Changes
- Removed automatic update notification system (was experimental)

### Bug Fixes
- Fixed various Lua errors

---

## Version 1.4.9
**Updated by Folktale**

### Changes

#### Simplified Bar Visibility Setting
- Replaced "Hide when not Ret" with a simple "Show bar" toggle
- Toggle ON: Bar is always visible (regardless of spec)
- Toggle OFF: Bar is hidden
- Provides cleaner, more intuitive control over bar visibility

#### Version Check Notifications
- Added automatic update notification system
- SwedgeTimer now exchanges version info with other users in your guild/party/raid
- Notifies you when a newer version is available on CurseForge
- Can be disabled in settings via "Update notifications" toggle

### Technical Details
- New `version_check.lua` module handles addon message communication
- Uses `CHAT_MSG_ADDON` event with "SwedgeTimer" prefix
- Broadcasts via GUILD, RAID, or PARTY channels
- Throttled to once per 30 seconds to minimize network traffic
- Persists highest seen version across sessions

---

## Version 1.4.8
**Updated by Folktale**

### Bug Fixes

#### Bar Not Showing on Login
- Fixed bar being invisible for Ret paladins after login
- Root cause: talent data not available during ADDON_LOADED event
- Now uses Two-Handed Weapon Specialization talent to detect Ret spec (more reliable than Repentance)
- Added delayed visibility re-check 1 second after login to catch late-loading talent data
- Bar now updates immediately when talents change (respec, leveling)

#### Twist Marker Latency Compensation
- Increased dynamic twist padding coefficient from 0.6 to 0.7
- Provides additional buffer for high-latency players
- Example: 180ms latency now gets ~187ms padding (was ~160ms)

### Technical Details
- Removed `has_repentance()` function, now using `is_player_ret()` which checks 2H Weapon Spec
- Added `C_Timer.After(1.0, ...)` in main.lua to re-check visibility after talent data loads
- Added `st.bar.show_or_hide_bar()` call to CHARACTER_POINTS_CHANGED handler
- Dynamic twist padding formula: `lag_calibrated_ms * 0.7 * 0.001`

---

## Version 1.4.7
**Updated by Folktale**

### Bug Fixes: Swing Timer Precision

#### Parry Haste Detection
- Added detection for when the player parries an enemy attack
- Parrying reduces your swing timer by 40% (but cannot go below 20% of weapon speed)
- Swing timer bar now updates immediately when parry haste is applied
- Fixes timing desync that could occur during heavy melee combat

#### Extra Attack Handling (Hand of Justice, Sword Spec, etc.)
- Fixed swing timer incorrectly resetting on extra attack procs
- Now properly tracks `SPELL_EXTRA_ATTACKS` combat log events
- Extra attacks from Hand of Justice, Sword Specialization, Windfury, and similar effects no longer desync the timer
- Uses a pending counter to distinguish extra attacks from normal swings

### Technical Details
- New `st.player.extra_attacks_pending` counter tracks queued extra attacks
- `SPELL_EXTRA_ATTACKS` event parsing added to `OnCombatLogUnfiltered()`
- `SWING_DAMAGE` and `SWING_MISSED` handlers now check pending extra attacks before resetting timer
- Parry detection added for `SWING_MISSED` events where player is the target with `miss_type == "PARRY"`
- Parry haste calculation: `new_timer = max(timer - 0.4 * weapon_speed, 0.2 * weapon_speed)`

---

## Version 1.4.6
**Updated by Folktale**

### New Feature: Twist Window Sound Alert
- Added audio notification when approaching the twist window
- 4 custom sound effects to choose from: Pop (default), Bubble Pop, Swoosh, Whoopee
- Sounds play through Master channel - audible even with in-game SFX muted (like DBM)
- Sound triggers slightly before the twist window marker to account for audio delay

### Settings
- New "Twist window sound" toggle in Behaviour section
- New "Sound effect" dropdown to choose your preferred alert sound

### Technical Details
- Sound files stored in `Sounds/` folder as OGG format
- Uses `PlaySoundFile(path, "Master")` to bypass SFX mute
- Sound timing includes 200ms offset for audio lead-in compensation
- Timing automatically scales with haste effects and lag compensation settings

---

## Version 1.4.5
**Updated by Folktale**

### Changes
- Removed LibClassicDurations dependency entirely
- Now uses native TBC Classic `UnitAura()` API for seal duration tracking
- This fixes potential client crashes on TBC Classic PTR related to LibClassicDurations

### Technical Details
- TBC Classic Anniversary's native `UnitAura()` returns duration/expirationTime for player buffs
- LibClassicDurations was designed for Classic Era where this data was hidden
- Removed library loading from `core.lua` and `SwedgeTimer.toc`
- Updated `player.lua` to use native `UnitAura("player", counter)` instead of wrapper

---

## Version 1.4.4
**Updated by Folktale**

### Bug Fixes
- Fixed addon failing to load after TBC Classic PTR update
- Updated LibClassicDurations to support TBC Classic (was only checking for Classic Era)

### Technical Details
- Modified `Libs/LibClassicDurations/core.lua` line 20 to allow `WOW_PROJECT_BURNING_CRUSADE_CLASSIC` in addition to `WOW_PROJECT_CLASSIC`

---

## Version 1.4.3
**Updated by Folktale**

### Bug Fixes
- Fixed deadzone marker not scaling when bar height is changed in settings
- Fixed seal icon not scaling when bar height is changed (when "Match bar height" is enabled)

### Technical Details
- Added `frame.deadzone:SetHeight(db.bar_height)` to `set_bar_size()` function
- Added `st.bar.set_icon_size()` call to `set_bar_size()` function

---

## Version 1.4.2
**Updated by Folktale**

### Changes
- Removed second GCD marker - only one GCD marker is now displayed (one GCD before swing)
- Changed default GCD marker color to red to match the "Don't Cast" warning color
- Removed icon border feature (seal icons now display without border option)
- Updated settings window title to "SwedgeTimer (Updated by Folktale)"

### UI Cleanup
- Simplified GCD marker settings (single "Enable GCD marker" toggle)
- Removed "Show icon border" and "Border color" options from Seal Icon settings

---

## Version 1.4.1
**Updated by Folktale**

### Features
- Integrated LibClassicDurations for accurate seal buff duration tracking
- Seal icon cooldown overlays now sync perfectly with actual buff durations
- Timer text now renders above cooldown overlay for better readability

### Bug Fixes
- Fixed cooldown animation refresh when recasting seals before expiration
- Reversed cooldown swipe animation (now fills up as seal duration depletes)
- Fixed "Hide when not Ret" visibility logic to properly check for Repentance talent
  - If player has Repentance talent, bar always shows (ignores setting)
  - If player doesn't have Repentance and setting is checked, bar hides
  - If player doesn't have Repentance and setting is unchecked, bar shows
- Fixed Seal of Righteousness color setting having no effect (was using Command color)

---

## Version 1.4.0
**TBC Classic Anniversary Compatibility Release**

### Major Changes
- Complete refactor for TBC Classic Anniversary (Interface 20505) compatibility
- All modern WoW APIs replaced with TBC Classic equivalents
- Bar direction corrected to fill left-to-right as intended
- All marker lines now working with texture-based implementation

### API Compatibility Fixes
- Replaced `CreateLine()` with texture-based vertical lines (TBC Classic doesn't support line objects)
- Added compatibility checks for `InterfaceOptions_AddCategory` (retail-only function)
- Added compatibility checks for `SetMinResize`/`SetMaxResize` (not available in TBC Classic)
- Fixed font string vertical justification (`SetJustifyV("CENTER")` → `SetJustifyV("MIDDLE")`)
- Fixed ColorPickerFrame callback for TBC Classic (`swatchFunc` must be set)
- Fixed marker color options to properly unpack color table values

### Bug Fixes
- Fixed bar filling direction (now correctly fills left-to-right)
- Fixed marker positioning (now anchored from left edge with correct offsets)
- Fixed twist window marker appearing at correct position before swing completes
- Fixed GCD markers positioning at correct intervals

---

## Version 1.3.1

### Features
- The deadzone has been adjusted to use a more accurate representation of the input lag
- The deadzone may now be calibrated by the user in the settings menu through use of a scale factor
  - If unable to twist just outside the deadzone, increase the scale factor
  - If able to twist inside the deadzone, decrease the scale factor

---

## Version 1.3.0

### Features
- Added finer control over when the bar is automatically hidden (no seal or out of combat conditions)
- New "deadzone" feature shows the region near the end of swing where player is locked into current seal due to latency
  - Enabled by default, can be disabled
  - Customizable deadzone alpha, texture, and color

### Bug Fixes
- Fixed a call that produced a lua error when player class is not paladin
- The backplane is now drawn on the same frame strata, reducing UI component overlap issues
- Fixed right text being drawn too close to the end of the bar; text now has more spacing from bar borders

---

## Initial Release

### Features
- Seal twisting timer bar for Retribution Paladins
- Visual swing timer with seal-based color changes
- Twist window marker showing optimal seal change timing
- GCD tracking and markers
- Judgement cooldown marker
- Lag compensation with calibration options
- Customizable bar appearance (colors, textures, fonts)
- Configurable marker behavior and offsets
- Visibility conditions (combat, seal active, talent requirements)
