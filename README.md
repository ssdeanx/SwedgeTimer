# SwedgeTimer

One universal swing-timer build for every supported WoW client family — no per-client downloads.

## 📋 Table of Contents

- [WoW UI Source](#-wow-ui-source)
- [Architecture](#-architecture)
- [Who Is This For](#-who-is-this-for)
- [Features](#-features)
- [Tech Stack](#-tech-stack)
- [Quick Start](#-quick-start)
- [Project Structure](#-project-structure)
- [Scripts Reference](#-scripts-reference)
- [Deployment](#-deployment)
- [Contributing](#-contributing)
- [Related Projects](#-related-projects)
- [Code of Conduct](#-code-of-conduct)
- [License](#-license)

---

## WoW UI Source

This repo contains the latest WoW UI source code. Branches should reflect the most recent patches to their respective clients:

- [wow-ui-source](/home/sam/wow-ui-source)

---

## 🏗 Architecture

A single Lua addon that detects its client family at runtime and branches there, instead of shipping
client-specific file trees. The only per-flavor artifacts are the TOC variants, which decide **which
files load**; everything else branches in Lua.

- **`compat.lua`** is the single cross-client layer. Family detection lives here (`wow_project_id`,
  feature probes), and every spell/aura/cast/cooldown/haste call is normalised behind `st.api.*`.
  The rule for the rest of the addon: never call a cross-client API directly.
- **Pure math modules** (`twist.lua`, `weave.lua`, `nextaction.lua`, `practice.lua`) contain no WoW
  API calls at all, so their behaviour is unit-testable offline.
- **WoW-facing modules** (`main.lua`, `bars.lua`, class modules, UI modules) wire events, frames and
  options to that pure core.
- **One clock**: every timestamp comes from the aligned high-precision clock behind `st.api.get_time()`.
- **One class hook**: `bars.lua` dispatches a per-frame `on_bar_update(self, hand)` to the active class
  module, which keeps class behaviour out of the frame code.

## 🎯 Who Is This For

Melee players who want an exact read on their swing timing and on-next-swing state, across the whole
classic line and beyond. The build ships class-specific assists for **Paladin** (seal twisting,
next-action guide, practice trainer), **Shaman** (spell-weaving breakpoint assist), **Warrior** and
**Druid** (queued on-next-attack colouring, rage awareness) and **Hunter** (queued Raptor Strike,
opt-in queued Steady Shot). Swing timers themselves work for every class.

## ✨ Features

### Supported Clients

| Client | Interface |
| :--- | :--- |
| **Classic Era / Season of Discovery (SoD)** | `11509` |
| **The Burning Crusade Classic Anniversary** | `20506` |
| **WotLK Titanforge** | `38002` |
| **WoW Forever** | `16001` |
| **Retail / Live (Midnight)** | `120100` |

### Swing timers

- Mainhand, offhand and ranged swing timers with per-class default configurations, fully customisable
  (size, position, textures, fonts, colours, texts).
- GCD markers (physical or spell duration) anchored to the bar end or riding the progress bar.
- Range finder that dims the timer when the target is out of range.
- WoW Forever: timers are driven by the client's native `PLAYER_SWING` events.

### Class assists

- **Paladin** — seal twisting support (twist window band, attempt/success feedback, lag calibration,
  optional sounds), the next-action guide (Crusader Strike / Command / Blood / twist with HOLD/RIDE),
  and the Twist Practice trainer (`/st practice`).
- **Shaman** — spell-weaving breakpoint marker, cast spark and clip warning for LB / CL / HW / LHW / CH,
  with Maelstrom Weapon stacks and live haste.
- **Warrior / Druid** — queued Heroic Strike / Cleave / Maul colouring and insufficient-rage indication;
  Blood Surge glow (warrior).
- **Hunter** — queued Raptor Strike colouring; opt-in queued Steady Shot detection.

### Guidance & UI
- **Cooldown HUD** (archive port): a per-class slot registry with swipes, GCD dims,
  mana/range tints, proc glow and trinket cooldown/proc/ICD tracking; paladin slots ship today.
- **Rotation label**: a standalone draggable label with four formats, alignment, fonts and
  visibility options; sound selects preview on hover.
- **Next-action guides**: paladin, warrior, druid, shaman and hunter drive one shared guide
  frame through a provider contract. The four new guides ship off until verified in client.
- **Design mode** (`/st design`): snap grid, alignment guides, drag/reset for every element,
  lock override with exact restore on exit.

### Tooling

- LibDataBroker data source for broker displays (Titan Panel, Baggage, and similar).
- `/st` (or `/swedgetimer`) opens the options; `/st practice` toggles the twist practice session.

---

## 🧰 Tech Stack

| Layer | Technology |
| :--- | :--- |
| Language | Lua 5.1 (WoW addon runtime) |
| Framework | Ace3 (AceAddon, AceDB, AceDBOptions, AceConfig, AceConsole, AceEvent, AceGUI) |
| Libraries | LibStub, CallbackHandler-1.0, LibWindow-1.1, LibSharedMedia-3.0, LibCustomGlow-1.0, LibRangeCheck-2.0, LibClassicDurations (Era/TBC), LibDataBroker-1.1, LibClassicSwingTimerAPI (classic line only), LibLatencyMonitor, LibGlobalCooldown |
| Verification | `lua5.1` + `luac5.1` + `luacheck` via `bash tests/run.sh` (24 steps: syntax, client-profile smoke tests, per-module state and guide-contract suites, TOC integrity, static wiring parity, lint) |

---

## 🚀 Quick Start

1. Copy the `SwedgeTimer` folder into the `Interface/AddOns/` directory of whichever client you play
   (for example `_classic_era_`, `_classic_`, `_retail_`, or the WoW Forever client's AddOns folder).
   The correct TOC is selected automatically by client flavor.
2. Log in. The swing timer bars appear; drag them while unlocked, or use `/st` to open the options.
3. Optional: `/st practice` starts the seal-twisting practice session (paladin).

---

## 📁 Project Structure

```
SwedgeTimer/
├── SwedgeTimer.toc                 # base load order (WotLK lineage)
├── SwedgeTimer_{Vanilla,TBC,Wrath,Cata,Mists,Mainline}.toc
├── main.lua                        # addon object, event wiring, swing/GCD/range orchestration
├── bars.lua                        # bar frames, layout, per-frame update, class hook dispatch
├── compat.lua                      # the single cross-client API layer + family detection
├── swing_source.lua                # WoW Forever swing engine (native PLAYER_SWING)
├── utils.lua, config.lua, config_presets.lua
├── option_tables.lua, option_table_presets.lua
├── twist.lua, weave.lua            # pure class math (unit-tested offline)
├── nextaction.lua, nextaction_ui.lua   # paladin next-action guide (engine + frame)
├── practice.lua, practice_ui.lua       # twist practice trainer (engine + session UI)
├── ldb.lua                         # LibDataBroker data source
├── classes/                        # per-class modules (druid, hunter, paladin, shaman, warrior)
├── Media/                          # textures + sound files
├── Libs/                           # vendored libraries (never edited locally)
├── tests/                          # offline verification harness
└── docs/                           # archived older builds (not part of the shipped addon)
```

## 📜 Scripts Reference

| Command | Description |
| :--- | :--- |
| `bash tests/run.sh` | Full offline verification (24 steps, must be 0 failed) |
| `lua5.1 tests/smoke.lua` | Client-profile simulation: family detection + compat API on each client family |
| `lua5.1 tests/toc_check.lua` | TOC integrity: path casing, duplicates, module coverage, load order |
| `lua5.1 tests/wiring_check.lua` | Static wiring parity: event registration, class-hook dispatch, init guards, API contract, clock rule |
| `lua5.1 tests/<suite>.lua` | Per-module suites: twist, weave, swing_source, shaman, warrior, hunter, hunter_window, druid, druid_energy, nextaction, guide_contract, the four `*_guide` suites, practice, hud, rotationtext, design |
| `luacheck .` | Lint (0 errors required; warnings are tracked) |

---

## 🚢 Deployment

1. Run `bash tests/run.sh` — it must report 0 failed.
2. Bump `## Version` in **every** `SwedgeTimer*.toc` variant and the `version` string in `main.lua`.
3. Update this changelog's `[Unreleased]` section into a dated version entry.
4. Load the addon in each supported client for the acceptance pass (see the checklist in the changelog
   or the release notes), then package the folder as-is — no build step exists.

---

## 🤝 Contributing

We welcome contributions from the community. Please follow these guidelines:

### Getting Started

1. **Fork** the repository.
2. **Create a feature branch**: `git checkout -b feat/your-feature-name`
3. **Commit** your changes using [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat:` — new feature
   - `fix:` — bug fix
   - `refactor:` — code change that neither fixes nor adds
   - `docs:` — documentation only
   - `test:` — adding or improving tests
   - `chore:` — maintenance, CI, dependencies
4. **Run the tests**: `bash tests/run.sh` (must end with `24 steps, 0 failed`).
5. **Lint your code**: `luacheck .` (0 errors; no new warnings).
6. **Push** and open a Pull Request.

### Pull Request Checklist

- [ ] `bash tests/run.sh` passes (0 failed)
- [ ] Tests pass (`lua5.1 tests/<suite>_state.lua` for the touched module)
- [ ] New behaviour has a state-suite check (or a wiring-check invariant) where it can be tested offline
- [ ] New code includes tests where applicable
- [ ] Documentation updated for public API changes
- [ ] PR title follows Conventional Commits format

### Development Tips

- New files must be added to **every** TOC variant in dependency order; `tests/toc_check.lua` enforces it.
- Never edit anything under `Libs/` — update the library from upstream instead.
- WoW API calls belong in `compat.lua`; pure math belongs in the pure modules so it can be tested offline.
- The real acceptance gate is loading the addon in a client; the harness cannot simulate the game.

---

## 🔗 Related Projects

| Project | Description |
| :--- | :--- |
| [wow-ui-source](/home/sam/wow-ui-source) | Reference branches of the WoW UI source per client, used to verify API differences |
| LibClassicSwingTimerAPI | The standardised swing timer API used on the classic client line |
| SuperSwingTimer | Reference implementation for enhancement shaman weaving behaviour |
| `docs/swedge/*` | Archived older SwedgeTimer builds (TBC-era and Forever/Project Epoch) kept for reference |

---

## 📄 Code of Conduct

This project adheres to the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/) code of conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the repository maintainers.

---

## ⚖️ License

Distributed under the **MIT License**. See [LICENSE](LICENSE) for more information.

---

<p align="center">
  <sub>Built with Lua, Ace3 and a lot of swing-timer math.</sub>
  <br>
  <sub>Part of the <a href="https://github.com/ssdeanx/SwedgeTimer">SwedgeTimer</a> ecosystem</sub>
</p>
