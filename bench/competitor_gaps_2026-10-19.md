# bench/competitor_gaps_2026-10-19 — competitor-gaps (READ-ONLY research)

Desk: competitor-gaps. Date: 2026-10-19. No addon files touched; no code.
Single new file per brief `bench/briefs/brief_competitor-gaps_2026-10-19.md`.
Extends (never re-derives): `bench/competitor_scan_2026-10-17.md`,
`bench/rogue_deep_2026-10-19.md` §3, `bench/discover_features.md`,
`bench/verify_bank.md`.

Evidence bar: per-claim CONFIRMED (source said it + citation) or UNCONFIRMED
in caps. CONFIRMED here means listing/snippet/page text, NOT in-client
behavior — nothing below is verified in-client.

## 0. Tooling log (brief: enumerate BOTH catalogs, record URL + what each tool returned)

Catalogs enumerated first in Code Mode: `search("firecrawl")` → full 28-tool
surface CONFIRMED present (agent/status/search/scrape/parse/map/crawl/
interact/monitor/research families); `search("searxng")` → instance_info /
suggestions / web_search / web_url_read CONFIRMED. Research ran on SearxNG,
per brief preference (small bodies, compact results throughout).
- `firecrawl_search` (developer query "swing timer seal twist energy tick
  tracker addon"): **Invalid request body** — same failure recorded in
  competitor_scan §6. Firecrawl search is unusable on this deployment.
- `firecrawl_developer_search` (same query): **HTTP 404** — endpoint absent.
- SearxNG `searxng_web_search` × 8 (SST update; NAG update; TellMeWhen;
  Gnosis; NugRunning/NugEnergy; Quartz; rogue WA energy/CP/poison; WST
  SixxFix/YAHT; ClassTimer; weapon-sync desync; ICD trackers; HST analytics;
  feral TTD). Engines brave/duckduckgo/startpage degraded (suspended/CAPTCHA,
  noted per call); google-cse carried all results.
- SearxNG `web_url_read` × 3: `https://nextaction.guide/addon` LOADED
  (marketing + capability text extracted, quoted §1); `https://addons.wago.io/addons/nag`
  EMPTY after conversion (JS wall — known wago limitation); CF file page
  `gnosis/files/890631` → **403** (CF bot-wall, standing limitation).
- CurseForge facts below are search-listing text (title/description/date),
  labeled as such. wago pack bodies unrended (listing/snippet text only).

## 1. What is NEW vs the prior corpus (current-state deltas only)

1. **SST is still actively updated.** Listing snippet (Oct 2026): "7 days ago
   ... tracks white-hit swing timers ... tuned for Classic/TBC mechanics such
   as next-melee-attack abilities, dual-wield desync" — CONFIRMED as listing
   text https://www.curseforge.com/wow/addons/super-swing-timer. File-page
   snippet: "3.1.0 - 2026-04-23. Added Blizzard Interface Options / AddOns
   registration ... reseal marker for twist seals and an opaque black default
   color" — CONFIRMED as listing text
   https://www.curseforge.com/wow/addons/super-swing-timer/files/8013102.
   New-vs-corpus: (a) native Settings-panel registration is now an SST
   feature — worth one check that our AceConfig panel registers on every
   flavor (no code this lane); (b) in-client reseal-marker behavior
   UNCONFIRMED.
2. **WST SixxFix is the maintained WST.** "Last Update: Sep 26, 2026 ...
   Total Downloads: 4.1M" — CONFIRMED as listing text
   https://www.curseforge.com/wow/addons/weaponswingtimer-sixxfix; Wowhead
   TBC hunter best-addons (Veramos, updated 2026/02/10) recommends it —
   CONFIRMED as snippet text
   https://www.wowhead.com/tbc/guide/classes/hunter/dps-addons. Base WST
   (2019) vs SixxFix (Sep 2026) split is now dated evidence, not inference.
3. **NAG went multi-client + deeper.** https://nextaction.guide/addon
   (LOADED 2026-10-19): "Covers Classic Era, SoD, TBC, Wrath and MoP";
   "Sim-informed APL-driven decisions"; "Class-specific timing bars ...
   weaving, twists, sync windows"; "Rotation editor ... Import an APL
   export"; "Performance modules"; "Cursor-anchored mode"; "Keybind labels
   and cooldown swipes"; "Encounter timing ... Pre-pull timeline, pull
   timers, and boss timing references." NAG core is now also a Wago addon
   (https://addons.wago.io/addons/nag — page exists, body unrended) and a
   WoWInterface listing (Mar 30 2025, "designed for seamless integration
   with other addons and WeakAuras" — snippet CONFIRMED
   https://www.wowinterface.com/downloads/info26918-NextActionGuideNAG.html).
   Net: the Hekili-style bar is now table stakes for the one-stop-shop
   north star on exactly our client set. Commercial/tebex layer unchanged
   from prior report.
4. **Warrior desync-alert pattern is current and packaged.** "Every Warrior
   Needs These Weakauras" (Mar 8 2026): "Battle/Commanding Shout WA:
   https://wago.io/HFvEcUnu4 ... Desync Alert WA: https://wago.io/jFIL_JaSw
   ... SwingTimerAPI Addon (required...)" — CONFIRMED as snippet text
   https://www.youtube.com/watch?v=_IpTaL1VcIY. Wowhead TBC warrior
   best-addons (Feb 10 2026): "A swing timer is essential ... make sure your
   weapons remain out of sync" — snippet CONFIRMED
   https://www.wowhead.com/tbc/guide/classes/warrior/dps-addons. WA-pack
   bodies UNCONFIRMED (unrended); desync math itself is offline-testable.
5. **ICD/trinket-status tracking is current on Anniversary.** Fojji Item &
   Trinket Tracker v1.0.11 (Sep 23 2026, "[2.5.6 - The Burning Crusade
   (Test)]", 16838 views) — snippet CONFIRMED https://wago.io/Z4Pm4SgBU;
   Warlock ICD+Trinket Timers https://wago.io/j47H1Zq3c and Quagmire ICD
   tracker https://wago.io/RbRPSbAV9 (notes "may not work as expected in
   ... Anniversary" — snippet CONFIRMED, Anniversary API drift is real).
   Gnosis changelog adds an "icd" command "to track procs/inner cooldowns"
   (file 890631 snippet — CONFIRMED as listing text). Three independent
   implementations = demand CONFIRMED at listing level.
6. **Rogue all-in-one HUD template exists for 2.4.3.** "Rogue 2.4.3
   EnergyTicker + HUD ... Energybar + Ticker ... Combo Points Poisons
   (Crippling & Wound) Actives (SnD, Rupture) CDs" — snippet CONFIRMED
   https://wago.io/UxkIny7oJ. Supports consolidating (not scattering) rogue
   widgets. Pack body UNCONFIRMED.
7. **Quartz lives on Midnight.** Quartz Redux/Midnight variant (Oct 10 2026)
   — snippet CONFIRMED https://www.curseforge.com/wow/addons/quartz-midnight.
   Castbar competition is alive on the newest client; our target/focus cast
   bars (discover #10) still have a live benchmark. In-client behavior
   UNCONFIRMED.
8. **ClassTimer is dead; Raven inherits.** "I had been using ... Classtimer
   since Burning Crusade. But after a update for War Within, Classtimer has
   not updated" — snippet CONFIRMED (guide comments). Buff/debuff-bar space
   consolidates to Raven/WA, not ClassTimer. No action (our bars cover it).
9. **HST post-fight hint re-confirmed.** "optimization hint after a fight,
   based on clipped shots and timing" (Jul 8 2026 listing) — snippet
   CONFIRMED https://www.curseforge.com/wow/addons/hunter-shot-timer.
   Strengthens the case for gap H4 below (was single-source; now re-sighted
   3 months later).

## 2. Per-class ranked gaps (delight × feasibility; implementable; owning files, no edits)

Rank = parser-delight × casual-delight ÷ effort. Effort S/M/L; Offline Y =
pure logic testable without a client. Owning files verified on disk
(`*.lua` glob 2026-10-19: per-class `classes/`, `*_guide.lua`, `hud.lua`,
`widgets.lua`, `rotationtext.lua`, `druid_energy.lua`, `hunter_ui.lua`,
`practice.lua`/`practice_ui.lua`, `compat.lua`, `bars.lua`).

### Hunter
- **H1 (rank 1, H/M, S, Y): target-of-target warning.** HST tracks "target
  warning state ... when your target's target is you" (prior corpus, §1
  re-sighted). Nobody in our hunter set surfaces it. Owner:
  `hunter_ui.lua` + `classes/hunter.lua` (UnitExists/UnitIsUnit reads, no
  CLEU). UNCONFIRMED in-client on Anniversary/Forever.
- **H2 (rank 2, H/M, M, Y-math): post-fight shot analytics.** HST's clip
  counter + "optimization hint after a fight" + "how much latency buffer
  you are using" (§1.9 re-CONFIRMED). Pure stats math over the swing log;
  presentation is a practice-report screen. Owners: `practice.lua` +
  `practice_ui.lua` (report) + `classes/hunter.lua` (clip counters).
  Narrower cousin of differentiator #1 (parse replay); HST proves demand.
- **H3 (rank 5, M/S, S, N): Feign Death resist alert — UNCHANGED from prior
  corpus** (Wowhead Bouk's/Feign-Death-Resist-Alert). No new evidence this
  round; kept for completeness, no new citation.

### Warrior
- **W1 (rank 1, H/M, S-M, Y): desync indicator.** Desync Alert WA
  (wago jFIL_JaSw) + Wowhead "remain out of sync" + SST "dual-wield desync"
  tuning (§1.1/1.4). Sync math is pure (two swing phases); presentation is
  an offhand spark tint on the MH bar (tazUI green-ideal/yellow-offhand
  precedent, prior corpus). Owners: `classes/warrior.lua` +
  `warrior_guide.lua` + `bars.lua`/`hud.lua` (spark tint). No new probe.
- **W2 (rank 4, M/S, S, N): Battle/Commanding-Shout reminder WA.**
  wago HFvEcUnu4 (Mar 2026 video) — shout-uptime widget with a named WA id,
  current. Overlaps banked buff tracking but the "Commanding-if-already-
  buffed" suppression rule (prior corpus) is the implementable edge.
  Owner: `warrior_guide.lua`. WA body UNCONFIRMED.

### Paladin
- **P1 (rank 3, H/M, S, Y): GCD-aware reseal marker.** SST 3.1.0 ships a
  "reseal marker for twist seals" (§1.1) — a marker computed from GCD +
  twist window, distinct from our twist band. `twist.lua` is WoW-free and
  the natural owner (pure marker-fraction math, same shape as `weave.lua`
  breakpoint math); presentation via the existing `on_bar_update` band
  hook in `bars.lua`; inputs gathered in `classes/paladin.lua`. SST
  in-client behavior UNCONFIRMED; marker math is offline-testable.
- **P2 (rank 6, M/M, M, N): NAG-depth encounter timing.** NAG's pull-timer /
  pre-pull timeline + performance modules (§1.3) exceed our twist score
  badge (P1 banked, shipped). Owners: `practice.lua` (score modules) +
  `rotationtext.lua` (text surface). Pull-timer input source on classic
  clients UNCONFIRMED (DBM/BW broadcast vs manual).

### Shaman
- **S1 (rank 3, H/M, S-M, Y-math): ICD/status row for trinkets+effects.**
  Icy Veins "internal cooldown status" WA + Fojji Anniversary tracker +
  Gnosis `icd` command (§1.5). Timer math is pure; aura/item reads via
  `compat.lua` probes. Owners: `hud.lua` (row) + `classes/shaman.lua`
  (inputs) + `compat.lua` (probe). Per-item ICD durations UNCONFIRMED
  (need in-client reads; Quagmire caveat shows Anniversary drift).
- **S2 (rank 7, M/M, M, N): totem management UI.** TotemAce "extra totems
  per element as dynamic buttons + Totem Twist mode" (prior corpus, no new
  evidence this round). COLLIDES with banked S1 (ids UNCONFIRMED). Recorded,
  not ranked higher — no new material.

### Druid
- **D1 (rank 2, H/M, S, Y): EMA TTD readout.** "Time to Kill" WA (Wowhead
  warrior page, prior corpus) + Sno TTD WA (rogue_deep §3) + verify_bank D4
  correction (EMA smoothing, TimeToDie-style). Pure math over HP deltas;
  feeds Rupture-vs-Eviscerate (rogue) and FB-vs-Shred (feral) decisions.
  Owner: pendant to `druid_energy.lua`-style helper (new small pure
  module mirroring `twist.lua`/`weave.lua` shape) + `classes/druid.lua`
  inputs. Smoothing constant UNCONFIRMED in-client (offline-tunable).
- **D2 (rank 5, M/M, S, Y): energy-tick predictor display.** Yam ticker
  (rogue_deep §2.2) + druid D5 (verify_bank STANDARD). `druid_energy.lua`
  exists; gap is the proc-aware tick clock (Combat-Potency-style grants
  must not re-anchor). Owner: `druid_energy.lua` + `classes/druid.lua`.

### Rogue (new class; first pass + rogue_deep hold, extended only)
- **R1 (rank 2, H/M, S-M, Y-math/N-probe): proc-aware energy-tick clock.**
  Yam ticker CONFIRMED best-in-slot on TBC (rogue_deep §2.2, re-sighted via
  rogue class page this round: "Show rogue energy bar with tick indicator"
  https://wago.io/tbc-weakauras/classes/rogue). Predictor math is pure;
  live deltas need UNIT_POWER reads. Owners: `rogue_guide.lua` (pure) +
  `classes/rogue.lua` (live deltas). Proc-disambiguation rule
  UNCONFIRMED in-client.
- **R2 (rank 4, M/H, S, N): MH/OH poison reminder + charges.** Sno
  "MH/OH no-poison reminder" + Poisoner one-click + UxkIny7oJ poisons-in-HUD
  (§1.6, rogue_deep §3). Presence via UnitAura/inventory reads; charges on
  Forever need tooltip/probe work — new-probe risk, UNCONFIRMED.
  Owners: `classes/rogue.lua` + `rogue_guide.lua`.
- **R3 (rank 6, M/M, S, N): short-CD row (Kick/Kidney/Re-stealth/Bandage)
  + multi-CD yellow glow.** Sno UI short-CD tracker + stacked-glow rule
  (rogue_deep §§2.4/2.7). Aura + cooldown reads only. Owners:
  `classes/rogue.lua` + `rogue_guide.lua` frame. Tunables (which CDs)
  UNCONFIRMED beyond Sno's list.

### Cross-class (affects all six; ranked once)
- **X1 (rank 2, H/M, S-M, Y): ICD status tracker.** §1.5 evidence (three
  independent implementations + Gnosis command). Owners: `hud.lua` +
  per-class gather inputs + `compat.lua`. Highest cross-class value per
  effort in this round.
- **X2 (rank 5, M/H, M, Y-templates): ready-made class HUD templates.**
  UxkIny7oJ (rogue), Warrior HUD packs, Sno suite — the WA pack is the
  benchmark for template quality (competitor_scan #15, still open).
  Owners: `design.lua`/`designmode.lua` + per-class guides. No new probe.
- **X3 (check, not build): Blizzard Settings-panel registration.** SST
  3.1.0 registers in Interface Options (§1.1). One verification check
  that our AceConfig panel appears on every flavor — options-lane
  follow-up, UNCONFIRMED until in-client.

## 3. Deliberately NOT re-proposed (prior corpus stands, no new evidence)
Enemy swing bar (shipped `enemy_swing.lua`); class power bars; hunter CD
group / debuff bars; paladin CD group; Rockbiter/shield charges; Omen proc;
Battle Shout; target/focus cast bars; mirror timers; latency bar; range
recolor; multi-spell bars; Masque; conditions engine; raid-CD + DR tracking
(TellMeWhen listing re-sighted §1 but no new shape); NAG authorship question
(competitor_scan §9, operator-owned); Forever restrictions; Titanforge gaps
(no source again this round — UNCONFIRMED, unchanged); Midnight specifics.

## 4. Uncertainty ledger (this round)
- All wago pack bodies unrended (JS wall); all CF facts are listing/snippet
  text; all YouTube facts are title/description text unless noted LOADED.
- Firecrawl search surfaces are broken on this deployment (search → invalid
  body; developer_search → 404); SearxNG carried the round.
- SST "7 days ago" / SixxFix "Sep 26 2026" / Quartz-Midnight "Oct 10 2026"
  are engine-relative listing dates; treat as approximate.
- No in-client verification exists for any item above; orchestrator feeds
  the next build wave, in-client testing decides.
