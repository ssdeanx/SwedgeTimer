# SwedgeTimer

One swing timer for every supported WoW client — mainhand, offhand, and ranged bars plus per-class assists, in a single download with no per-client package.

## Supported clients

| Client | Interface | Swing timers |
| :--- | :--- | :--- |
| Classic Era / Season of Discovery | `11509` | <span style="color:#00FF00">Live</span> |
| TBC Anniversary | `20506` | <span style="color:#00FF00">Live</span> |
| WotLK Titanforge | `38002` | <span style="color:#00FF00">Live</span> |
| WoW Forever | `16001` | <span style="color:#00FF00">Live</span> (native swing engine) |
| Retail / Live (Midnight) | `12.1.x (120100, 120105)` | <span style="color:#808080">Static by design</span> (bars inert, one-time notice) |
| Cataclysm Classic | `40402` | <span style="color:#808080">Static by design</span> (bars inert) — **not a supported client** |
| Mists Classic | `50500` | <span style="color:#808080">Static by design</span> (bars inert) — **not a supported client** |

The Cataclysm and Mists rows are the two extra TOC flavours the build ships. They deliberately
omit the swing-timer library, so they load with the same inert stand-in as Retail — the HUD,
rotation label, design mode and options still work, the bars never move. They are **not**
supported clients: there is no live swing engine, so the rotation scenario is refused there.

## Screenshots

PENDING — screenshots to be added. No images yet.

## Install

**CurseForge app (recommended):** search `SwedgeTimer`, install, keep it updated through the app.

**Manual:** download the zip, copy the `SwedgeTimer` folder into your client's `Interface/AddOns/` folder (for example `_classic_era_`, `_classic_`, `_retail_`, or the WoW Forever client's `AddOns` folder), then log in. The correct file list is picked automatically per client flavor — there is nothing else to choose.

## Slash commands

- <span style="color:#FFD700">`/st`</span> — open options
- <span style="color:#FFD700">`/st practice`</span> — toggle the practice trainer
- <span style="color:#FFD700">`/st design`</span> — toggle layout mode
- <span style="color:#FFD700">`/st diag`</span> — print a diagnostic report (include it verbatim when reporting an issue)

## Classes

| Class | Guide | Cooldown HUD | Practice drills |
| :--- | :--- | :--- | :--- |
| <span style="color:#C79C6E">Warrior</span> | Slam / Execute / Overpower, Sunder / Rend upkeep, stance-dance | HS / Cleave queue tints, Blood Surge, Slam, Overpower | Core order, Core window, Sunder upkeep, Execute burn, HS/Cleave queue, Pre-pull opener |
| <span style="color:#F58CBA">Paladin</span> | Seal-twist window, next-action (CS / Command / Blood / twist), SoD variants | Holy Shock, Aura Mastery, seals, How | Twist timing, FCFS priority, Prepull seal, Judgement fit |
| <span style="color:#ABD473">Hunter</span> | Steady / weave / LnL prompts, trap tracking, distance band | Steady, Raptor, Rapid Fire, LnL / OOM badges | Shot priority, Clip, Cooldown pops, Opener |
| <span style="color:#FFF569">Rogue</span> | Pool-vs-spend, Eviscerate-first / Rupture-first, Shiv / Tea context | SnD, Rupture, EA, AR, BF, Cold Blood | Finisher order, Combo-point decision, SnD upkeep, Opener |
| <span style="color:#FF7D0A">Druid</span> | Bite / Rip, FF fishing, RipCP override | Maul queue, TF / Berserk, Claw, energy trackers | Cat priority, Shift rule, Roar upkeep, Execute |
| <span style="color:#0070DE">Shaman</span> | Weave fits, sub-5 LB / LvB, totem upkeep | Shocks, Stormstrike, totems, Searing | Enhancement priority, Stack decision, Stormstrike decision, Totem upkeep |

All six classes ship a **rotation scenario** (the class's own rotation, run end to end and
graded) and **three to six focused drills** each (one skill apiece). A drill is a focused
single-skill trainer; the scenario is the full rotation sequence. The paladin's drill list
leads with the twist timing drill — the twist minigame belongs to the paladin, and a class
that publishes no drills of its own is refused rather than handed someone else's.

## Practice

`/st practice` runs drills against the same sim rotations the guides use (sourced from the [wowsims](https://github.com/wowsims) APLs — run your own numbers at [<span style="color:#1E90FF">wowsims.com</span>](https://www.wowsims.com)). Each drill grades <span style="color:#FFD700">S</span> through <span style="color:#808080">F</span> and stays unscored when the setup can't be judged — a safe place to rehearse pooling, swing timing, and windows before raid. Nothing in practice affects your live bars.

Three practice modes, chosen in options → Practice: the **class session** (the default), the
**rotation scenario** (your class's own rotation, ten decisions, graded as a sequence), and
the **drill list** (one button per focused drill). A read the client cannot answer scores
nothing — the addon never guesses a grade.

Each rotation scenario follows the class's own sim priority list — the **full** list, not just
the damage rows. The utility layer is in it too: the warrior's stances, Bloodrage, Battle
Shout, Recklessness and Death Wish; the hunter's Rapid Fire, Serpent upkeep, aspects and Kill
Shot; the rogue's Vanish, Preparation and Premeditation; the druid's Cat Form, Leader of the
Pack and Innervate; the shaman's Strength of Earth, Mana Spring, Frost Shock and Bloodlust;
the paladin's Hand of Reckoning and Hammer of Wrath. The rows the sims carry as **pre-pull**
(Charge, Intercept, the Battle Shout, Cat Form, Strength of Earth, Sanctity Aura, …) live in
a per-class pre-pull table instead of the combat rotation, and the pre-pull drill grades the
opening sequence — the warrior's, the hunter's and the rogue's ship one that grades the
utility rows; the paladin's grades the pre-pull **seal**, and the druid's and the shaman's
carry their pre-pull rows as citations only. The scenario is timed off the swing, so it needs
a live swing engine: on a client with the inert stand-in (Retail) it is refused with a
message rather than ten unknown steps.

Practice is a progression, not just a scoreboard: every graded attempt earns **XP**, XP
raises your **level** (50 per class, then **renown**), each drill carries its own **mastery**
and tier (Unranked → Bronze → Silver → Gold → Platinum), and **streaks** track sessions and
days. The **Progress** options page shows the level, the XP bar, the per-drill mastery
table, the achievements and the lifetime stats (runs, accuracy, time active, best score);
its stats frame draws the accuracy **sparkline** over your last 50 sessions. The practice
panel carries a level badge and a session XP bar. Everything is local to your own profile —
there is no account, no telemetry and no export.

## HUD & designer

Every class ships a cooldown HUD: ability slots with swipe, glow, and tint (queue states, procs, OOM), plus counters where they matter. Instead of configuring every element, pick a ready-made layout template per class in options — three curated templates for each of the six classes (18 in all, plus a Custom fallback), setting slots, sizes, and spacing in one click; any manual tweak drops back to Custom. `/st design` previews and arranges bars, HUD, rotation text and the practice elements live. Template looks were researched from popular WeakAuras layouts (links only, nothing copied).

<span style="color:#FFA500">Retail bars are intentionally static; HUD, rotation label, design mode, and options still work there. The addon never invents a reading: an unknown value is reported as unknown, and a practice step that cannot be decided scores nothing rather than a wrong grade.</span>

## Links

Project pages — CurseForge (search `SwedgeTimer` at [<span style="color:#FF8000">curseforge.com</span>](https://www.curseforge.com)), with Wago and WoWInterface listings. Exact project-page URLs unconfirmed; no links invented here. The addon itself integrates with none of them.

## Repository map

This repository is both the addon and the workshop where it is built.

| Path | What it is |
| :--- | :--- |
| `README.md` | this file — the workshop map |
| `workshop.md` | the workshop — rooms, desk flow, lessons |
| `AGENTS.md` | operating mechanics — conventions, gotchas, cross-engine rules |
| `CAIRN.md` | the operating disposition |
| `hands-up.md` | the escalation ledger — open questions and verdicts |
| `desks/` | one directory per desk: `desks/<name>/journal.md` and `.signals/`; `desks/journal.md` is the central lane ledger |
| `bench/` | shared results — findings, verdicts, reports; `bench/briefs/` holds dispatch briefs, `bench/lessons.md` holds lessons |
| `tests/` | offline checks — `bash tests/run.sh` |
| `classes/` | one module per class — druid, hunter, paladin, rogue, shaman, warrior |
| `Libs/` | vendored libraries — Ace3, swing-timer engine, range check |
| `docs/` | archived addon builds and design notes |
| `Media/` | textures, fonts, sounds |
| `*.toc` | load orders — base plus one per client flavor |
| `*.lua` | addon modules (layout in `AGENTS.md`) |
| `CHANGELOG.md` | release history |
| `LICENSE` | GPL-3.0 |

## License

GPL-3.0 — see `LICENSE`.
