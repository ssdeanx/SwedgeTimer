# competitor_scan_2026-10-17.md — competitor-scan, research round 2

Desk: competitor-scan (READ-ONLY research; no code touched, no git mutations — one read-only `git status` was used to verify my own write set). Date: 2026-10-17.
North star scored against: SwedgeTimer as the ONE-STOP SHOP (swing timer + bars + WeakAuras-style class HUDs + timers). Parser value first, casual second. Constraints: single universal build (classic-line + mainline, runtime branching only), no non-vendored dependencies, pure logic offline-testable = high priority.

**Tooling note (honest):** all 28 Firecrawl tools were enumerated in Code Mode (`search("firecrawl")` → 28 paths). The MCP tool surface is broken on this deployment: `firecrawl_search` rejects every body (`Invalid request body`, even `{"query": "..."}` alone), `firecrawl_agent` rejects (`Unrecognized key in body`), `firecrawl_developer_search` 404s, `firecrawl_find_tools` requires an Alexandria API key the team does not have. Research therefore ran against the same self-hosted Firecrawl instance (:3002) via its REST API (`POST /v2/search`, `POST /v2/scrape`) plus SearxNG (:8069) JSON — real calls, small bodies, every URL cited below. JS-rendered pages need `waitFor ≥ 6000 ms` (wago.io pack pages, Wowhead guides). wago.io pack bodies embed only WA import strings; pack titles/versions are cited, feature lists are UNCONFIRMED.

---

## 1. Direct swing-timer competitors — newer versions and new entrants

### 1.1 Super Swing Timer (SST) — v0.2.3, much deeper than the round-1 inventory
Source: https://www.curseforge.com/wow/addons/super-swing-timer (scraped 2026-10-17; version text on page: "Current version: v0.2.3. Status: release-ready."; search-listing snippet says updated "5 days ago" — recency UNCONFIRMED, version CONFIRMED from page text).

New material beyond `bench/discover_features.md` (all page-text CONFIRMED unless marked):
- **Dual-client CLEU architecture:** "Classic Era `COMBAT_LOG_EVENT` payloads use numeric spell IDs; TBC Anniversary sends localized spell names (strings) instead." Their swing-reset lookup tables are keyed by name on Anniversary. This is a correctness landmine for every CLEU consumer we ship on Anniversary (twist chain, swing resets, hunter H1). NEW.
- Paladin: "aura-aware seal breakpoint logic … red twist zone … plus a **GCD-aware reseal marker**" — a reseal point marker is a concept our twist lane does not list.
- Shaman: weave assist for **LB / CL / Healing Wave / Lesser Healing Wave / Chain Heal** with "highest-known-rank spell resolution per family" (rank-aware resolution technique; healer spells are beyond our S-lane scope).
- Druid: "**Ravage** now gets an opener-ready amber cue when Cat Form Ravage is actually usable"; Maul queue tint path.
- Hunter: "hunter-linked MH bar that only appears for real melee swings or queued **Raptor Strike** (dynamically anchored above the ranged bar), a yellow Raptor queue tint, configurable movement-safety".
- Warrior: "Parry haste handling using the standard Classic **40% reduction with a 20% remaining-time floor**" (formula; verify_bank §5 #8 only said "parry-haste adjustment" exists).
- Off-hand: "requires a real off-hand weapon speed instead of fabricating hidden OH cycles"; "haste rescaling when weapon speed changes mid-swing".
- UX: "when unlocked for setup, right-click now preserves camera mouselook"; compact spark defaults.

### 1.2 WeaponSwingTimer (WST) fork family — the maintenance-fork situation
- Base: https://www.curseforge.com/wow/addons/weaponswingtimer ("tracks your's and your target's swing timers… Auto Shot timing").
- **SixxFix** fork: https://www.curseforge.com/wow/addons/weaponswingtimer-sixxfix — recommended by Wowhead's TBC hunter page (below) and by redditors ("I use WeaponSwingTimer Sixxfix").
- **Fixed 07/2026** fork: https://www.curseforge.com/wow/addons/weaponswingtimer-fixed-07-2026 ("Supports all melee weapons, Hunter's Auto Shot, and wands").
- **-SpanoWare** fork: https://www.curseforge.com/wow/addons/weaponswingtimer-spanoware ("tracks main-hand/off-hand and target swing timers, handles Slam resets and parry haste, and optionally shows Auto Shot/Wand bars to prevent clipping").
- **MoP/Forever variant**: https://www.curseforge.com/wow/addons/weaponswingtimer-mop (Nov 23, 2025; "Weapon swing timer for melee and range atacks"). Its "Team" sidebar also lists a Forever addon titled **"Default auto atack swing timer Forever"** — URL/details UNCONFIRMED (title only, seen in sidebar).
- **YAHT mode**: WST has a built-in "YAHT" setting — "a linear timer that shows when you need to cast before to avoid clipping" (reddit r/classicwow 1sda8pa comment, CONFIRMED as user claim). YaHT itself: https://www.wowinterface.com/downloads/info25049-YaHT-YetanotherHunterTimer.html (Classic 1.13.2, 2019) + reference guide https://www.briankoponen.com/yaht-addon-vanilla-world-warcraft/.

### 1.3 SwingTime — new (Classic Era), https://www.curseforge.com/wow/addons/swingtime
- "Four bars — main-hand, off-hand, ranged (hunter Auto Shot + wands), and your target"; LibSharedMedia textures/fonts per bar; profiles; drag+lock.
- "Correctly handles haste, parry-haste, Windfury/extra attacks, weapon swaps, and the hunter Auto Shot cast window."
- "On-screen warnings — big, centered **OUT OF RANGE** and **NOT ATTACKING** text."
- Collision notes: OUT OF RANGE warning overlaps H4 (range gate) in spirit; profiles overlap C5; per-bar LSM textures add a LibSharedMedia dependency we would not take.

### 1.4 Hunter Shot Timer (HST) — new, https://www.curseforge.com/wow/addons/hunter-shot-timer
- "Tracks auto shots, cast windows, and target-warning state in real time… how much latency buffer you are using, and whether your timing is clipping shots or overlapping."
- Steady Shot cast overlays; **target warning when your target's target is you**; Auto/Manual latency mode; clip threshold; themes/icons; RAG indicator.
- **Combat analytics**: "generate an optimization hint after a fight, based on clipped shots and timing patterns" — post-fight self-review without external tools. Relates to bench differentiator #1 (parse replay), narrower scope.
- Author _bel_ also ships **Class Guide** (https://www.curseforge.com/wow/addons/class-guide, Oct 4, 2026): "Stat priorities, gear comparisons, rotation guidance, Skill Compendium, spellbook assistance, leveling talents, and Hunter/Warlock pet abilities with Grimoire tracking — **all in one addon for WoW Forever**" (sidebar text on the HST/CopyChat pages; CONFIRMED as listing text). A direct one-stop-shop competitor on Forever.

### 1.5 EllesmereUI — UI suite with a WoW Forever swing timer
- https://www.curseforge.com/wow/addons/ellesmereui — release notes: v9.2.1 "Quality of Life: Swing Timer (WoW Forever) — Main-hand, off…" (https://www.curseforge.com/wow/addons/ellesmereui/files/8927870); v9.2.2 "WoW Forever — Resource Bars: Swing Timer…" (…/files/8936131); v9.3 "The Swing Timer's Off Hand and Ranged bars no longer vanish… after your attack speed change" (…/files/8988935). So a mainstream UI suite already ships MH/OH/ranged swing bars **on Forever**.
- Community friction: r/WowUI "[Addon] EllesmereUI Swing Timer" — hunter reports the swing timer not showing while enabled (https://www.reddit.com/r/WowUI/comments/1x2vnml/addon_ellesmereui_swing_timer/).
- Companion: **ElvirUI** (https://www.curseforge.com/wow/addons/elvirui, Oct 4, 2026) — adds "swing timer right under it; Interrupts…", never edits EllesmereUI files.

### 1.6 Forever native UI swing timers — competitive baseline, details UNCONFIRMED
- Thread: "Swing Timers are natively in the WoW Forever UI now, here's how to set them up." — https://www.reddit.com/r/classicwow/comments/1wk7sw4/swing_timers_are_natively_in_the_wow_forever_ui/ (title CONFIRMED; comment seen: "Are any hunters using the built in ranged swing timer? Do you like it?"). Body/setup steps UNCONFIRMED (old.reddit returned a 2FA wall; `.json` scrape failed).
- Supporting: video "How To Get Weapon Swing Timer and Bags on WoW Forever" https://www.youtube.com/watch?v=ECKH_V2XvKw ("without having to track down addons"); earlier thread "Forever, and Swing Timers" https://www.reddit.com/r/classicwow/comments/1whuoxs/forever_and_swing_timers/ (pre-launch speculation: "Warriors got a talent to not reset the swingtimer when using slam").
- **Implication:** on Forever, SwedgeTimer's swing bar is no longer the only one in the room — native UI + EllesmereUI + a WST Forever variant + a dedicated "Default auto attack swing timer Forever" exist. Differentiation there = class HUD/timers/guides, not the bar itself.

### 1.7 Reddit demand signals (timers)
- "Weapon Swing Timer Addon?" (Jan 2026, Anniversary): https://www.reddit.com/r/classicwow/comments/1qdvltv/weapon_swing_timer_addon/ — answers: wago.io/B2G4lZKVE, "WeaponSwingTimer - TBC Anniversary".
- "Is there a swing timer that helps with seal twisting: TBC?" (Jan 2026): https://www.reddit.com/r/classicwow/comments/1qd608o/is_there_a_swing_timer_that_helps_with_seal/ (comments recommend WST; a WeakAura castbar https://wago.io/bNtdbWZ-W appears in the hunter thread).
- "Best Hunter shot timer?" (Apr 2026): https://www.reddit.com/r/classicwow/comments/1sda8pa/best_hunter_shot_timer/ — WST + YAHT setting; SixxFix; castbar WA bNtdbWZ-W.
- "is there any weapon swing bar add-on for melee in midnight?" (r/wow 1srfr59): https://www.reddit.com/r/wow/comments/1srfr59/is_there_any_weapon_swing_bar_addon_for_melee_in/ — reply points to melee-range addons instead; **Midnight swing-bar availability UNCONFIRMED**.

---

## 2. WoW Forever ecosystem wave + confirmed client restrictions

New addons targeting Forever specifically, all Sep–Oct 2026 (dates from listing snippets):
- **Counterclock** (https://www.curseforge.com/wow/addons/counterclock) — enemy cooldown tracker for PvP/arena/duels. Description confirms Forever restrictions: "WoW Forever hides other players' spells from addons: no combat log, no enemy casts, no enemy buffs in combat." Uses (a) manual key-bound tracking for escapes/defensives ("press a key when they use one"), (b) self-starting timers when CC lands, (c) **the game's own voice to announce enemy casts** ("The game's own voice says each spell your opponent starts casting: 'Polymorph'") — a native-TTS alert pattern; cast-length inference ("a warrior's 1.5 second cast can only be Slam").
- **DoT-kill predictor** (reddit, https://www.reddit.com/r/classicwow/comments/1wpanvw/made_a_small_addon_for_forever_that_shows_if_your/) — "shows if your DoTs will kill the target" on nameplates. Confirms restrictions: "can only track your own casted DoTs… no party, no procs"; hidden values worked around "all via simple math" (parses spell descriptions + observed tick sizes).
- **Forever Trinket Menu** (https://www.curseforge.com/wow/addons/forever-trinket-menu, "6 days ago") and **Forever Trinkets Menu Redux** (https://www.curseforge.com/wow/addons/forever-trinkets, "7 days ago") — "compact trinket bar… optional automatic switching, priority queues, per-character profiles". TrinketMenu lineage also live for BCC Anniversary (https://www.curseforge.com/wow/addons/trinketmenu-bcc-anniversary, Jan 25, 2026).
- **ForeverBuildLab** (https://www.curseforge.com/wow/addons/foreverbuildlab, Oct 9, 2026) — "Build planning and simulation addon… create, compare, and optimize character builds."
- **StatCoach** (https://www.curseforge.com/wow/addons/statcoach, "4 days ago") — "Your **weapon skill** against its maximum and what the missing points cost you in crit, plus Defense against 440 for tanks. Stat priority from…" — weapon-skill readout is a classic melee parse feature absent from our lists.
- **Polestar Guides** (https://www.curseforge.com/wow/addons/polestar-guides, "1 day ago") — "A free, open-source guide addon for World of Warcraft: Forever"; **Azeroth Codex** (https://azerothcodex.up.railway.app/priorites) — external class guide/gear-priority site with an addon.
- Threat-on-nameplates for Forever: **KP_TPlate** (https://www.curseforge.com/wow/addons/kp-tplate, Oct 6, 2026 — "threat alert addon based on native nameplates… see who in a mob group is targeting you") and **myAggro Plates** (https://www.curseforge.com/wow/addons/myaggro-plates, Sep 24, 2026).
- Other Forever utilities: **Forever Discovery Log** (…/forever-discovery-log), **SNRN Rummage – Smart Consumables** (…/snrn-rummage, Oct 5, 2026), **Classic Frames Forever**, **CopyChat** — see their CF pages via https://www.curseforge.com/wow/addons/copychat sidebar.
- Forever hunter auto-shot behavior is in flux (client-side changes): "Auto Shot and Wanding Cast Time Reduction in WoW: Forever Not Intended - Will Be Fixed" (https://www.reddit.com/r/classicwow/comments/1wob3c1/), "Hunter's auto shot is getting fixed (nerfed)" (https://www.reddit.com/r/wowforever/comments/1wob5g0/), "Blizzard Intentionally Removed One of Hunter's Most Engaging Mechanics in WoW: Forever" (https://www.reddit.com/r/classicwow/comments/1wpbvrf/). Do not hardcode Forever auto-shot timing. Details UNCONFIRMED.
- Forever guides exist on Icy Veins (e.g., https://www.icy-veins.com/wow-forever/holy-priest-healer-pve-guide, Sep 17, 2026) and Mobalytics (https://mobalytics.gg/wow-forever/classes/priest-leveling-guide-1-60 — "Haste… does not scale HoTs or DoTs in Forever").
- **Titanforge/Titan Reforged behavior: no source found this round — UNCONFIRMED (unchanged from discover_features #35).**

---

## 3. wago.io suite depth

- Flavor categories now include **Forever imports** (https://wago.io/forever-weakauras, "Search Forever Imports"), **Titan Reforged WotLK** (https://wago.io/titan-reforged-wotlk-weakauras), TBC (https://wago.io/tbc-weakauras), Classic (https://wago.io/classic-weakauras), MoP (https://wago.io/mop-weakauras). Per-class filter pages exist per flavor (e.g., https://wago.io/tbc-weakauras/classes/paladin).
- SoD packs (titles/versions CONFIRMED via SearxNG + page loads; feature lists UNCONFIRMED — pages render as import strings):
  - Sabimaru – Paladin Classic [SoD] v1.4.5-32: https://wago.io/zLJ2R3Oua · Sabimaru – Shaman Classic [SoD]: https://wago.io/8MyJNekEa
  - swingtimer SOD v1.0.0 (community swing-timer WA for SoD): https://wago.io/fLyWyqQFV
  - Cludes | Classic Paladin 2.0: https://wago.io/Y7SYk2ATp · Lucky Doubloon – SoD: https://wago.io/fHFe56H04
- Wrath/Titan Reforged HUD packs (the "WeakAuras-style class HUD" benchmark): Warrior HUD (Wrath) v1.0.19 https://wago.io/lal9N2RsR · Warrior Pack WOTLK https://wago.io/cUtf1eTHO · Warrior Wotlk https://wago.io/ixLhk_w9x.
- Dual-wield swing/sync WAs (multiple independent implementations): "Warrior swing timer w/ offhand tick v1.0.1" https://wago.io/4b8pTHJB2 (references "Swing Timer - Weapon Sync by Gingerbread") · "Fury Swing Timers v1.0.17" https://wago.io/r_4W0tpYR ("Offhand should now work with all locales") · "**Desync your swings!** v1.0.6" https://wago.io/-RZz3vfC- ("Alerts you with an icon and lightsaber sound when your weapons are synced, so you can press your desync macro") · "tazUI: SwingTimer v3.0.5-15" https://wago.io/fDDNP0SM7 ("The spark will be green for ideal sync, yellow for offhand…") · "Swingtimer offhand v1.0.0" https://wago.io/9hi_2ldMR.
- Hunter cast-window WA used in threads: https://wago.io/bNtdbWZ-W; seal-twist thread WA: https://wago.io/B2G4lZKVE.

---

## 4. Per-class "best addon" guidance (Icy Veins + Wowhead)

Icy Veins TBC class pages (all updated Jan 12, 2026 per search snippets; CONFIRMED page loads): hunters / warriors / paladins / shamans / druids `-best-addons` under https://www.icy-veins.com/tbc-classic/. Newly surfaced names not in either bench report:
- **PallyPower** (paladin) — "simplifies the process of assigning Paladins to specific blessings to specific members of the raid by providing a simple overlay for buffing."
- **TrinketMenu** (shaman/druid PvP sections) — "makes trinket swapping a breeze… configurable trinket menu."
- **"internal cooldown status!"** (shaman) — a WeakAura showing trinket/effect ICD state.
- **Weapon syncing WeakAura** (shaman page changelog, 2021) — sync-state visualization.
- **Combat timer WA** ("shows a timer when you are in combat") and **Gladdy**-style arena frames ("diminishing return tracker for CC with enemy frames and cast bars… tracks enemy trinket and racial usage… interrupt lockouts").
- WotLK pages: https://www.icy-veins.com/wotlk-classic/{hunters,warriors,paladins,druids}-best-addons ("Auto Shot timer and a melee swing timer. These are absolute necessities…").

Wowhead per-class addon pages (render with waitFor 8000):
- Hunter: https://www.wowhead.com/tbc/guide/classes/hunter/dps-addons — **Bouk's Buff Duration Tracker** (buff/trinket timers, "add any additional buffs/trinket timers by adding the spell ID"), **Feign Death Resist Alert** (alerts when Feign Death resists in combat), **SixxFix WeaponSwingTimer**, BigWigs (DBM alternative), Details!, AtlasLoot.
- Warrior: https://www.wowhead.com/tbc/guide/classes/warrior/dps-addons — a WA whose "spark indicates the off-hand swing progression, **to track that your weapons aren't synced**"; **"Time to Kill"** WA (time until target HP reaches 0 — TTD, generalizes banked D4); Battle Shout / **Commanding Shout-if-already-buffed** reminder WA; "Warrior Important Debuffs on target" WA; WST warrior module ("changing color when Heroic Strike or Cleave are queued" — verify_bank §5 #2); attunement tracker; **a sim-export addon**: "creates a line of code that you can seamlessly copy and paste into **WoWSims**".
- Paladin (served Classic-era content): https://www.wowhead.com/tbc/guide/classes/paladin/dps-addons — threat meter ("required addon for raiding"), swing timer, **OmniCC** pairing, debuff-timer addon (name truncated in scrape).

---

## 5. Rotation helpers (the biggest competitor category for the north star)

- **Next Action / NextActionTBC (NAG)** — https://www.curseforge.com/wow/addons/next-action (Oct 9, 2026): "Hekili-style rotation helper for TBC Classic (including Anniversary-era clients)… horizontal or vertical queue: upcoming spells, cooldowns, interrupts, and optional survival items… class/spec APL logic (priority lists) aligned with common TBC PvE guidance (e.g. Icy Veins style priorities)." Rotation modes Auto/Single/Cleave/AoE; trash/boss context; consumables suggestions (Healthstone → healing potion → mana potion below sliders); **Paladin (Ret): seal priority list, optional Seal Twisting, JotC opener logic, reaction/latency sliders, Smart Mana, lane indicator**; profiles with export/import string (NATBCv2); themes (default/ElvUI-like/NDui-like/minimal), mini mode, cast bar on lead icon, range highlight, sound on priority change; `/natbc rotdiag`; "throttling and optional raid hardening". Companion ecosystem: https://nextaction.guide/ ("Classic WoW rotation coach paired with NAG Helper") and https://nag.tebex.io/ ("Battle.net-integrated access system… Designed by top theorycrafters") — **commercial**. YouTube: "This Addon Tells You EXACTLY What to Press | TBC Anniversary" (Jan 12, 2026) https://www.youtube.com/watch?v=ma5d8YMih5U; "One Addon Fixes TBC Rotations For Every Class" (May 4, 2026) https://www.youtube.com/watch?v=hZw0THFhZYY. **Name/feature collision with our in-repo paladin nextaction guide — authorship relation UNCONFIRMED; flag for operator.**
- **Hekili** — https://www.curseforge.com/wow/addons/hekili: retail priority helper; listing states "Hekili is **not compatible with the Midnight (12.0) expansion**" (Nov 1, 2025). Retail rotation helpers are being killed by API restrictions; classic-line is where they live now.
- **ShockAndAwe** (enhancement, historical) — https://www.curseforge.com/wow/addons/shockandawe + ShockAndAwe_Bars https://www.curseforge.com/wow/addons/shockandawe_bars; the classic enh helper lineage (mostly covered by our S-lane + known items).
- **TotemAce** — https://www.curseforge.com/wow/addons/totemace (Jan 22, 2026, TBC Anniversary, Ace3): totem management, extra totems per element as dynamic buttons, **"Totem Twist mode adds an animated…"**. Directly in S1 territory (banked, BLOCKED on ids).

## 6. DoT/timer trackers and parse plumbing

- **NugRunning** — https://www.curseforge.com/wow/addons/nugrunning: "Multi-Target Timers for DoTs, Buffs, Cooldowns", 1.9M+ downloads. Reddit: "Ellipsis… + NugRunning seem abandoned" per user (https://www.reddit.com/r/classicwow/comments/1qjgl2m/any_dot_timer_addon_reccomendations_for_tbcc/); a Medium guide calls NugRunning "mandatory" for feral DoT tracking (https://medium.com/@doantruongpxiob9646/the-best-wow-addons-for-classic-2026-after-3-000-hours-6167e84d673f). **NugEnergy** (…/nugenergy) is the rage/energy bar sibling.
- **LoggerHead** — https://www.curseforge.com/wow/addons/loggerhead (auto combat-log enabler per zone/instance; Lite variant https://www.curseforge.com/wow/addons/loggerheadlite); wowcoach.gg (Feb 24, 2026) says "two are actively maintained for Midnight" (https://wowcoach.gg/blog/how-to-enable-combat-logging-wow). Parse-enabler — parsers literally cannot WCL-parse without logs.
- **NKThreat** — threat meter for Classic Era (seen in CurseForge category listing, https://www.curseforge.com/wow/search?class=addons&page=1&pageSize=20&sortBy=relevancy&categories=tank); threat remains covered by discover_features #34.
- Midnight combat-addon changes (context for Mainline/Retail): https://www.reddit.com/r/wow/comments/1oe8ucc/how_midnights_upcoming_game_changes_will_impact/ — Blizzard "making gameplay more intuitive and approachable—without requiring addons"; addons trending toward "skins of the base UI"; one new API noted ("colorize unit frame health bars in combat"); trinket/potion tracking questioned in comments. Specifics UNCONFIRMED.

---

## 7. Ranked TOP-15 (new material only)

Value: H/M/S = would-this-bring-a-WA/Quartz/SST-user-home, parser first. Effort: S/M/L. Offline: Y = pure logic testable without a client; N = needs in-client data. Overlap references `desks/journal.md` lanes and bench ids.

| # | Feature | Source URL | Parser | Casual | Effort | Offline | Overlap verdict |
|---|---------|-----------|--------|--------|--------|---------|-----------------|
| 1 | Multi-class Hekili-style rotation suggestion queue (modes, trash/boss context, consumable suggestions, profile export string, paladin seal-twist tuning) | https://www.curseforge.com/wow/addons/next-action · https://nextaction.guide/ | H | H | L | Y (logic) | COLLIDES-with-lane-plan (paladin nextaction guide exists in-repo; practice C1) — the market leader is commercial and broader; decide scope before the options pass |
| 2 | Multi-target DoT/bleed timers (feral Rip/Rake/Lacerate, multi-target Flame Shock etc.) | https://www.curseforge.com/wow/addons/nugrunning · https://medium.com/@doantruongpxiob9646/the-best-wow-addons-for-classic-2026-after-3-000-hours-6167e84d673f | H | M | M-L | N (multi-unit aura scans; Forever limits) | NEW (discover #4 is hunter single-target; #14 is one-bar-many-spells — multi-target is new) |
| 3 | Trinket/effect internal-cooldown (ICD) status tracker | https://www.icy-veins.com/tbc-classic/shamans-best-addons ("internal cooldown status!") · https://www.wowhead.com/tbc/guide/classes/hunter/dps-addons (Bouk's tracker) | H | M | S-M | N (timer math Y) | NEW (P5 references DST timing but no ICD tracker; P2/P3 unaffected) |
| 4 | Dual-wield weapon-sync / desync indicator (offhand spark on MH bar, sync coloring, desync alert) | https://wago.io/-RZz3vfC- · https://wago.io/4b8pTHJB2 · https://wago.io/fDDNP0SM7 · https://www.wowhead.com/tbc/guide/classes/warrior/dps-addons | H | M | S-M | Y (sync math) | NEW (enemy-swing lane is target swings; warrior lane lists no sync feature) |
| 5 | Post-fight shot analytics + optimization hints (clip counts, latency buffer, timing patterns) | https://www.curseforge.com/wow/addons/hunter-shot-timer | H | M | M | Y (stats math) | NEW; narrower cousin of bench differentiator #1 (parse replay) — HST proves demand |
| 6 | Weapon-skill readout (missing points → crit cost; Defense vs 440) | https://www.curseforge.com/wow/addons/statcoach | H | M | S-M | N (skill API; math Y) | NEW (no lane; classic melee meta feature) |
| 7 | Gear/sim export string (copy into WoWSims) | https://www.wowhead.com/tbc/guide/classes/warrior/dps-addons | H | M | M | Y (string builder) | NEW (C5 parse presets = profile import/export, different artifact) |
| 8 | CLEU localized-name fallback for TBC Anniversary (payloads send spell names, not ids) | https://www.curseforge.com/wow/addons/super-swing-timer | H | n/a | S-M | Y (name tables) | COLLIDES-with-lane-plan (compat-bl C2 aura scan + twist CLEU chain robustness; correctness requirement, not optional) |
| 9 | Auto combat-logging per zone/instance (parse enabler) | https://www.curseforge.com/wow/addons/loggerhead | H | S | S | N | NEW (no lane; "one-stop" plumbing) |
| 10 | DoT-kill prediction (will my DoTs finish the target — own DoTs only on Forever) | https://www.reddit.com/r/classicwow/comments/1wpanvw/made_a_small_addon_for_forever_that_shows_if_your/ | M-H | M | M-L | Y (math) / N (data) | NEW (D4 TTD is banked but is HP-velocity, not kill prediction) |
| 11 | Trinket auto-rotation / priority queues + swap menu | https://www.curseforge.com/wow/addons/forever-trinkets · https://www.curseforge.com/wow/addons/trinketmenu-bcc-anniversary | M-H | M | M | N (item APIs) | NEW (C5 touches profiles only) |
| 12 | Totem management UI + twist mode | https://www.curseforge.com/wow/addons/totemace | M | M | M | N (GetTotemInfo) | COLLIDES-with-bank-S1 (totem twist, ids UNCONFIRMED) — TotemAce shows the space is already served on Anniversary |
| 13 | Feign Death resist alert | https://www.wowhead.com/tbc/guide/classes/hunter/dps-addons | S-M | S | S | N | NEW (verify §5 #9 is ranged-reset handling, different mechanic) |
| 14 | Special-attack queue tints beyond HS/Cleave (Raptor Strike, Maul) | https://www.curseforge.com/wow/addons/super-swing-timer | M | S | S | N | COLLIDES-with-lane-plan (warrior HS tint) + NEW extensions for hunter/druid |
| 15 | Ready-made class HUD templates (Wago HUD packs as the benchmark) | https://wago.io/lal9N2RsR · https://wago.io/cUtf1eTHO | M | H | M | Y (templates) | BUILDING-now (bars+design C6 registration+templates) — benchmark for template quality |

Deliberately excluded (known or out of scope): enemy swing bar, class power bars, hunter CD/debuff groups, paladin CD group, Rockbiter/shield charges, Omen proc, Battle Shout tracking, target/focus cast bars, mirror timers, latency bar, range recolor, multi-spell bars, Masque, conditions engine, sounds/text/counters, raid-CD + DR tracking, SoD rune packs, 4-state range helper, aspect icon, flight bar, tradeskill merge, facing/target-count/aggro sensors, Titanforge gaps (all in discover_features.md); safe-to-move, HS/Cleave tint, ShieldBlock bar, energy-tick bar, totem timer bar, JotC uptime, target swing timer, parry-haste adjustment, feign-death reset, readiness refresh (verify_bank.md §5); H1–H7, W1–W7, P1–P7, D1–D7, S1–S7, C1–C6 (bank).

## 8. Extend-not-repeat statement

This round adds beyond `bench/discover_features.md`: (1) the current version landscape of the direct competitor (Super Swing Timer v0.2.3 — dual-client CLEU name-vs-id handling, GCD-aware reseal marker, healer-weave ranks, Ravage cue, parry-haste 40%/20% formula) and the WeaponSwingTimer maintenance-fork family; (2) four new swing/timer entrants not previously inventoried (SwingTime, Hunter Shot Timer, EllesmereUI's Forever swing timer, the WST MoP/Forever variant + "Default auto attack swing timer Forever"); (3) the Oct-2026 **WoW Forever addon wave** (Counterclock, trinket menus, ForeverBuildLab, StatCoach, Polestar/Azeroth Codex, KP_TPlate/myAggro threat plates, Class Guide by _bel_) and the confirmed Forever API restrictions (own-DoTs only, hidden values, no enemy spells/casts in combat, native-TTS pattern); (4) wago.io flavor depth including Forever/Titan Reforged/SoD categories and the dual-wield weapon-sync WA cluster; (5) per-class guidance from Icy Veins (Jan 2026 refresh: PallyPower, TrinketMenu, ICD-status WA, weapon-syncing WA, Gladdy-class frames) and Wowhead (Bouk's tracker, Feign Death Resist Alert, Time-to-Kill WA, sim-export string, SixxFix); (6) rotation-helper competition (NAG/NextActionTBC commercial Hekili-style helper for TBC; Hekili dead on Midnight) and the parse-plumbing category (LoggerHead, NugRunning multi-target DoTs); (7) mechanics constraints that change implementation (Anniversary CLEU localized names; Forever auto-shot churn; Midnight addon restrictions). Everything else from those two reports was checked and skipped.

## 9. Uncertainty markers

- **Forever native UI swing timer**: thread title + a hunter comment are evidence; setup/behavior UNCONFIRMED (thread body not retrievable: old.reddit 2FA wall, `.json` scrape failed).
- **"Default auto attack swing timer Forever"**: title seen only in a CF sidebar; URL/details UNCONFIRMED.
- **Titanforge/Titan Reforged-specific swing behavior: no source found this round — UNCONFIRMED** (unchanged from discover_features #35).
- **SoD ids**: not re-verified; all SoD rune ids remain UNCONFIRMED (verify_bank §2 stands).
- **wago.io pack feature lists** (Sabimaru, Cludes, swingtimer SOD, Warrior HUD): pages render as import strings; titles/versions cited, features UNCONFIRMED.
- **NAG/NextActionTBC vs our in-repo nextaction guide**: name + feature collision; authorship/relationship UNCONFIRMED — operator decision required (if it is not ours, it is the single strongest competitor to the north star; if it is ours, this report is a feature-gap list for it).
- **Midnight (12.x) restriction specifics**: thread-level info only; exact API surface UNCONFIRMED; "Hekili not compatible with Midnight" is from its CF listing.
- **HST analytics / EllesmereUI Forever swing timer / Counterclock voice**: description-and-release-note level; in-client behavior UNCONFIRMED.
- **Reddit comment claims** ("Swing Timers are natively in the WoW Forever UI") are user claims, not vendor documentation.
- **Search-snippet dates** ("5 days ago", "4 days ago") are engine-relative; treat recency as approximate.
