# rogue_deep_2026-10-19 — Rogue deep pass: SS verdict, speedrun tech, competitor teardown, addon handoff

Desk: rogue-deep. READ-ONLY: no addon files touched. Single new file per brief
`bench/briefs/brief_rogue-deep_2026-10-19.md`.
Date: 2026-10-19. Extends `bench/rogue_research_2026-10-19.md` — read it first,
nothing below re-derives it. Cross-refs use §numbers into that file.

Evidence bar: per-claim CONFIRMED (source said it + citation + clients) or
UNCONFIRMED in caps. CONFIRMED = the cited source states the claim (guide text,
listing text, or labeled player claim). Tooling: SearxNG MCP
(`searxng_web_search` + `web_url_read`) preferred; Firecrawl catalog enumerated
in Code Mode (`search("firecrawl")` → agent/status/search/scrape/parse/map/
crawl/interact/monitor/research families CONFIRMED present); wago.io pack bodies
unrended as before (listing/snippet text only — same known limitation as the
first pass). CurseForge page bodies 403 via `web_url_read` (bot-walled);
CF facts below are search-listing text, labeled as such.

## 0. Prior-corpus boundary (not re-searched, reused by pointer)

- Rogue rotation/priority per client, energy 20/2s + pooling bands (65/85 TBC),
  Combat Potency, SnD/Rupture/Envenom rules, Vanish/Overkill, poisons, caps:
  first pass §§1–2.
- SST rogue set (SnD bar, energy-tick helper, SS end-window red slice, tick
  cadence): first pass §0 / `discover_features.md` §Rogue.
- Anniversary CLEU sends localized spell NAMES not numeric ids (single-source
  page-text claim, UNCONFIRMED) → oracle R1: any rogue CLEU matching (Shiv,
  poison procs, Vanish/Overkill windows) on `_TBC` needs name-fallback tables.
- Forever restrictions (own-DoTs only, hidden values, no enemy spells/casts):
  `competitor_scan_2026-10-17.md` §2. Rogue CLEU chains are dead on Forever;
  build on UnitAura/power/CP reads or stay inert with a stated reason.
- WotLK Feint-threat conflict, FoK 5+/6+ conflict, Titanforge deltas, exact
  SnD/Rupture tables, Kick lockouts, MH/OH metas: first pass §§5–6, unchanged.

## 1. MUST-ANSWER (1): "SS after MH swing" — verdict

### VERDICT: CONFIRMED on Classic Era (classic 1.13/1.15 engine, incl. Era/SoD
### family clients); REFUTED-as-unneeded on TBC Anniversary 2.5.6+ (and by
### extension any post-normalization client). No source pulled for WotLK
### Titanforge 3.80.2 either way → UNCONFIRMED there (expected TBC-like, not
### sourced).

**CONFIRMED — Classic Era.** ClassicRogueCraft "Rogue Swing Timing Guide – How
to time swings for extra +dps" (Sno, Classic Era 1.13/P6 frame, simmed ~90s
fight in P6 BiS via Simonize sim):
"**Swing timing is timing your attack ability (sinister strike, backstab or
eviscerate) to happen right after your character auto attacks with your
mainhand weapon**… The reason you swing time is because certain things (sword
spec and windfury mainly) can proc, which will **reset your auto attack before
it completes. If your swing is reset before it finishes, you gain no damage
from that auto attack.**"
Simmed gains, perfect timing (0.1s after every swing): Horde sword **+35 dps**,
Alliance sword +7, Horde dagger +11. Average timing (0.2s, no swing-timing
during AR): Horde sword +26–27, Alliance sword +4–5, Horde dagger +6–7.
"**Alliance dagger rogues do not have to worry about swing timing because they
do not have windfury or sword spec procs**."
Citation: https://classicroguecraft.com/swing-timing-guide/ (page loaded
2026-10-19; video version https://www.youtube.com/watch?v=qUaUmdKjsLM).

Corroborating player claims (labeled as such):
- Barrens Chat "Swing Timer? Why do I care?" (Jan 2020, Classic 1.13):
  "Things that proc an extra hit (such as Sword Specialisation and HoJ) reset
  your mainhand swing timer… **It's much better to be using Sinister Strike
  just when your MH swing timer came off cooldown (so right when your MH swing
  goes off)**, because like that proccing Sword Spec/HoJ is much less likely
  when your mainhand swing timer is almost ready."
  Citation: https://barrens.chat/viewtopic.php?t=2908 (page loaded 2026-10-19).
- r/classicwow dhzxix (Oct 15 2019): "You want to sinister strike right after
  your main hand attack." Citation: snippet-level CONFIRMED
  https://www.reddit.com/r/classicwow/comments/dhzxix/ (search-result text).
- MMO-Champion 2507421 (Sep 4 2019): "extra hits from sword spec reset the
  auto attack timer. And sinister strike has a chance to proc an extra hit."
  Citation: snippet-level CONFIRMED
  https://www.mmo-champion.com/threads/2507421-Classic-Rogue-Energy-amp-Swing-Timers.
- Odealo Classic rogue leveling guide: "Sinister Strike immediately after your
  Main Hand Weapon hits… additional Attacks from the Sword Specialization
  Talent reset your Swing Timer." Citation: snippet-level CONFIRMED
  (search-result text; page not loaded).
- Direct addon precedent — wago.io "Sinister Strike Timing v2.0.2-4"
  (W4bb8CdVO): "**Displays an icon right after a main hand melee swing has
  happened, in order to maximize the use of Sword Specialization/HoJ/…**"
  Citation: snippet-level CONFIRMED https://wago.io/W4bb8CdVO (pack body
  unrended — known wago limitation; title/description text cited).

**REFUTED-as-unneeded — TBC Anniversary (2.5.6).** Sno's TBC Rogue PvE FAQ
(same author as the Era swing-timing guide, so the change of advice is
load-bearing): "**Do I need to to time my swings/abilities in TBC? Nope!
Swing timing isn't needed in TBC because your abilities are no longer getting
reset.** This is why there's no swing timer weakaura in my updated UI."
Citation: https://www.tbcguides.gg/rogue-talents-enchants-gems/ (page loaded
2026-10-19). Mechanic reading: TBC normalized instant attacks so yellow hits
no longer reset the swing timer — the Era reset mechanism the whole technique
rests on is gone. (Engine-change statement is inference from the guide's
"no longer getting reset" + the removed WA; no engine-patch note pulled —
flag as DESIGN INFERENCE, not a sourced patch citation.)
Client/patch statement: holds on Classic Era 1.15.9 (`_Vanilla`) per Era
sources; does NOT hold on `_TBC` 2.5.6 per Sno TBC FAQ. SoD 1.15.x (`_Vanilla`,
same binary family): UNCONFIRMED — same classic engine suggests it holds, but
no SoD source ties Mutilate/Saber Slash (rune instant attacks) to swing-reset
behavior. WotLK Titanforge 3.80.2 (`_Wrath`): UNCONFIRMED — expected TBC-like
(no reset), no source pulled. Forever 1.60.1 / Retail 12.1.x: technique is
meaningless (no Sword Spec/HoJ/WF reset mechanics) — NOT APPLICABLE.

**Addon consequence:** the SS-after-swing cue is an Era-only widget. Gate on
family (`_Vanilla`) + sword-spec-relevant loadout, never a global default.
On `_TBC`+ the same screen space should NOT show a swing-timing cue (Sno
deliberately removed it) — showing one would contradict the best guide on
that client.

## 2. MUST-ANSWER (2a): speedrun / parse / hidden techniques (NEW vs first pass)

Each item: claim + citation + addon-signal handoff. "Handoff" names the exact
signal and whether the existing five-class patterns already expose it
(`ST.<CLASS>.gather_guide_inputs` frozen-spec + live reads; `bars.lua`
per-frame `on_bar_update`; paladin CD-group / druid D4 EMA / shaman weave-band
patterns from the first pass §4).

1. **Swing timing (Era Horde swords).** Above §1. Handoff: MH swing phase
   (already have via swing engine) + **post-swing cue window ~0.1–0.2s after
   MH land** (new presentation only — the "SS end-window red slice" SST
   already ships is the exact precedent; first pass §0). Maps to
   `on_bar_update` success-tint/glow, same as the paladin twist-band pattern.
   No new probe. Forever: `swing_source.lua` PLAYER_SWING can drive it;
   Retail stand-in never swings → widget stays hidden (swing-activity gate,
   never `st.is_mainline` — standing rule).

2. **Energy-tick prediction + pooling bands.** First pass §3.1 (20/2s,
   65-pre/85-post TBC bands) + NEW corroboration: Sno's TBC UI ships a
   "**Rogue Energy Bar + Ticker** — simple energy bar with an added ticker to
   show your current energy tick cycle. **This is more accurate than nugenergy
   and similar energy tickers because it doesn't get confused by energy procs
   from gear/talents. Big thank you to Yam from rogue discord for the energy
   ticker code.**" Citation: https://www.tbcguides.gg/rogue-ui/ (loaded
   2026-10-19). Wowhead TBC Rogue DPS Best Addons (Simonize, updated Feb 10
   2026) recommends "**Yam's Rogue Energy Tick Overlay** on Wago" + NugEnergy
   ("displays your energy resource… shows the tick rate") — citation:
   snippet-level CONFIRMED https://www.wowhead.com/tbc/guide/classes/rogue/dps-addons
   (guide body JS-blocked; snippet text cited). Dedicated addons: NugEnergy
   (d87_, 2.1M+ downloads, "Bar for Energy, Rage, etc. Also Energy Ticker in
   Classic") — CF listing text CONFIRMED
   https://www.curseforge.com/wow/addons/nugenergy; Rogue Energy Ticker
   (Mar 20 2026, "made for official client (Burning Crusade Anniversary
   edition). Adds an energy ticker to the player's energy bar") — CF listing
   text CONFIRMED https://www.curseforge.com/wow/addons/rogue-energy-ticker;
   BarEnergy-TBC ("Energy/Rage/Mana bar with tick timer for WoW TBC
   Anniversary… Rogue | Energy + Tick Timer") — CF listing text CONFIRMED
   https://www.curseforge.com/wow/addons/barenergy-tbc. Handoff: `energy_now`
   + `energy_tick_in` (first pass §4 names both) — needs a NEW probe: tick
   predictor math (2s cadence anchored on observed energy deltas, proc-aware
   per Yam — Combat Potency 15-energy grants must not re-anchor the clock).
   Template: druid D5 energy-deficit countdown (verify_bank D5). No CLEU shape.

3. **Thistle Tea (+ Flame Cap psychopath tech).** Wowhead TBC rogue rotation
   (Feb 10 2026): "**Thistle Tea, along with racial abilities and…**" +
   "offensive cooldowns such as Blade Flurry, Adrenaline Rush…" — snippet-level
   CONFIRMED https://www.wowhead.com/tbc/guide/classes/rogue/dps-rotation-cooldowns-abilities-pve.
   Sno P3 DPS Guide professions/consumes: "**Flame Cap – for psychopaths who
   want to cycle these into their Thistle Tea rotation** (honestly really not
   worth)" — CONFIRMED https://www.tbcguides.gg/rogue-p3-dps-guide/ (loaded
   2026-10-19). wowtbc.gg combat rogue: "Miscellaneous. **Best: Thistle Tea**,
   Scroll of Strength V…" — snippet-level CONFIRMED
   https://wowtbc.gg/class-guides/combat-rogue/. Sno TBC FAQ consume list
   includes Thistle Tea; his PvE cooldown bar "**tracks your cd on active
   trinket, BF, AR, Tea, LW drums and Haste Potions**" — CONFIRMED
   https://www.tbcguides.gg/rogue-ui/ (loaded). Handoff: item-ready cue
   (count + cooldown) — NEW probe (`GetItemCount`/`GetItemCooldown`, no CLEU).
   Maps to paladin P5 AW-drill consumable pattern + NAG consumable suggestions
   (competitor_scan §5). Energy-deficit gating ("use at low energy") reuses
   the tick predictor from #2.

4. **Vanish windows (threat / Overkill / MoS) — immunity tricks UNCONFIRMED.**
   First pass §3.6 covers Vanish→Overkill (WotLK), Vanish→Master of Subtlety +
   AR pairing (SoD), Vanish-as-threat (Era). NEW: Sno TBC UI buff tracker
   includes "**Vanish improved stealth buff**" and the short-CD tracker shows
   "**Re-stealth CD**" — CONFIRMED https://www.tbcguides.gg/rogue-ui/. Against
   parse-level "vanish immunes mechanic X" claims: the only loaded evidence
   cuts the other way — Sno P3 Winterchill notes "I have tried cloaking
   [Death and Decay] but I still took damage… cloak needs further testing,"
   i.e. immunities are mechanic-specific, not blanket. Any per-boss
   vanish/Cloak-immune table: UNCONFIRMED (no boss-mechanic source pulled).
   Handoff: Overkill/MoS window buff + re-stealth CD — UnitAura reads only
   (no CLEU needed unless matching the Vanish cast itself on Anniversary →
   oracle R1 name-fallback applies).

5. **Weapon-swap macros (OH-swap for poisons, Wrath ranges).** CONFIRMED as
   player/listing claims: r/classicwow 17fbh09 (Oct 2023) — "**Switching
   weapons causes both a GCD, and resets swing timers.**"
   https://www.reddit.com/r/classicwow/comments/17fbh09/ (snippet-level).
   Vanilla wiki rogue macros — "switch weapons invokes the Global Cooldown.
   **And it resets the swing timer**" — snippet-level CONFIRMED (search text;
   page not loaded). Wick's "Poisons and Things" (CF, Sep 27 2026): "**weapon
   swap keys** for a dagger opener… **swapping resets your swing timer**" — CF
   listing text CONFIRMED
   https://www.curseforge.com/wow/addons/wicks-poisons-and-things (page body
   403; listing text cited). Forever: conquestcapped Forever rogue leveling —
   "**A swap triggers the global cooldown and resets your swing timer, so
   press the macro twice**" — snippet-level CONFIRMED (search text; Forever
   client). TBC relevance: warcrafttavern rogue weapons — "a weapon swap may
   be very much necessary to apply mind…" (Mind-Numbing) — snippet-level
   CONFIRMED https://www.warcrafttavern.com/tbc/guides/rogue-best-weapons/.
   Wrath: Simonize "HOW & WHY To Swap Rogue Weapons in Wrath" (Jan 11 2023,
   Rod of the Sun King / energy-proc context) — title-level CONFIRMED
   https://www.youtube.com/watch?v=MB_TziMmSwY (body not pulled; swap
   specifics UNCONFIRMED); Warmane 455713 ("After your Killing spree ends,
   swap back your offhand to the faster axe. **This part is questionable by
   many pro rogues**") — recorded CONFLICT, snippet-level.
   Handoff: swap-action tint keyed to swing phase (swap right after MH land,
   same window as #1) — presentation only, no new probe; MUST carry the
   GCD+reset cost in the widget copy so it never reads as free. OH-swap for
   Mind-Numbing/Crippling is the TBC-relevant case (first pass §3.8).

6. **Opener sequencing in speedruns — guide openers CONFIRMED, speedrun
   deltas UNCONFIRMED.** Guide openers per client are in the first pass §§1.1–
   1.6. NEW speedrun-flavored evidence is CD-management, not opener changes:
   Sno P3 Hyjal — "**you should be very aware of your 2 min and 5 min CDs.
   You should use full CDs at wave 1** to get your CDs back up faster, and
   you should also keep in mind the **'point of no return' for 2 min and 5
   min CDs** (the point where you cannot use CDs or they won't be back up in
   time for the boss)"; boss swaps (demonslaying for demons, agility/flask
   otherwise, sharpening-stone-on-trash → Deadly-for-bosses) — CONFIRMED
   https://www.tbcguides.gg/rogue-p3-dps-guide/. No speedrun-log/WCL source
   pulled (WCL bot-walled, standing limitation) — any "top-100 opener differs
   from the guide" claim: UNCONFIRMED.

7. **AR+BF (+trinket/pot) stacking windows.** First pass §1.3 (Icy Veins
   stacking rules). NEW presentation precedent: Sno TBC buff tracker
   "**highlighted with a yellow glow to make it stand out when using multiple
   CDs at once**… Adrenaline rush / Blade Flurry / Slice and Dice / Expose
   Armor / Rupture / LW haste drum buff / Haste potion buff / Crusader-mongoose
   procs / … / Active trinket buffs" — CONFIRMED
   https://www.tbcguides.gg/rogue-ui/. Handoff: stacked-state icon group —
   reuse the paladin P2/P6/P7 CD-group pattern verbatim (first pass §4
   already maps this). No new probe (aura + cooldown reads).

8. **Blade Flurry cleave positioning — geometry UNCONFIRMED.** BF-as-cleave +
   "hits 1 extra target" is in the first pass (§§1.3–1.4) and SST/WST
   document the cleave; no source pulled on positioning geometry (facing,
   range, target-count sensor behavior in raid). Pack-size gates (FoK 5+/6+)
   stay with the first pass's recorded conflict + tunable default.

## 3. MUST-ANSWER (2b): competitor teardown — rogue (extends, never repeats)

Prior inventories this extends (not re-listed): SST rogue set + WST fork
family + SwingTime/HST/Ellesmere (competitor_scan §§1–2); TellMeWhen/Quartz/
Gnosis/ClassTimer (discover_features); NugRunning/NugEnergy, NAG (competitor
§§5–6); KPI threat plates, StatCoach, LoggerHead (competitor §§2,6).

| # | Competitor | Rogue signals it tracks | SwedgeTimer mapping (`on_bar_update` / guide-frame) |
|---|---|---|---|
| 1 | Sno TBC rogue WA suite (tbcguides.gg/rogue-ui — the per-client best-in-class author; TBC 2.5.x) | Circular CP + 1s-GCD ring; energy bar + Yam tick-corrector; buff tracker (AR/BF/SnD/EA/Rupture/drums/haste-pot/Crusader/Mongoose/Vanish-stealth/Sprint/Evasion/FAP/racials/trinkets, yellow glow on multi-CD); short-CD tracker (Kick/Kidney/Re-stealth/Ghostly/Bandage); enemy CC+debuff column; PvP CD HUD; PvE CD bar (trinket/BF/AR/Tea/drums/haste-pot); Time-To-Die WA; Redtuzk stats (hit/exp/crit calc); Hemlock (poison buying); Poisoner (one-click apply + **MH/OH no-poison reminder**) | CP pips + GCD ring = druid D3 pips pattern; ticker = #2 probe; buff/short-CD groups = paladin CD-group pattern; TTD = druid D4 EMA reuse; MH/OH poison reminder = new two-slot imbue badge (UnitAura/inventory reads; poison CHARGES on Forever need tooltip/probe work — flag as new-probe risk) |
| 2 | PepsiRogue (wago 1v8uT8TfF, TBC-WA) | CP + Energy Bar ticker + timers for Crusader, SnD, Weapon Swings; energy bar revealed in combat | Same three widgets; combat-reveal behavior = nil-safe show rule (standing toggle semantics) |
| 3 | Sinister Strike Timing WA (wago W4bb8CdVO) | Post-MH-swing icon maximizing Sword Spec/HoJ use (+energy requirement gate) | Exact precedent for §2.1's post-swing cue; energy gate = pooling-band tint from first pass §1.3 (65/85) |
| 4 | Slice and Dice + CP + Energy (wago dOTQ7JwQU) | Minimalist SnD timer + CP + energy | Minimal-mode template for the rogue guide frame (first pass §4) |
| 5 | Classic Rogue WAs collection (wago vcucOW5xl) | Poison tracker left of combo bar (+ combo bar) | Poison-uptime widget; charges-vs-duration split on Forever per first pass §1.5 |
| 6 | Rogue Energy Ticker (CF, Mar 2026, Anniversary) / BarEnergy-TBC / NugEnergy (2.1M DL) | Standalone energy(+tick) bars; BarEnergy covers Rogue/Druid/Warrior | If rogue.lua ships its own ticker, these are the displace-or-coexist decision (same call as SST energy-tick helper coexistence) |
| 7 | Wick's Poisons and Things (CF, Sep 2026; Era/Forever-era poison tooling) | One-click poison application, weapon-swap keys for dagger opener, MH/OH coating reminders; listing states swap-reset rule | Poison-application helper is out of swing-timer scope (note as boundary); swap keys + reset rule feed §2.5's tint |
| 8 | Wowhead TBC Rogue DPS Best Addons (Simonize, Feb 10 2026 — the closest thing to a vendor "best" list for `_TBC`) | Yam's Energy Tick Overlay WA + NugEnergy; (page body JS-blocked, list membership from snippet text) | Confirms the tick-predictor (#2) as THE rogue addon slot on TBC — higher parser value than any swing cue on that client (consistent with §1's TBC refutation) |
| 9 | WST family / SwingTime (prior corpus, rogue-relevant slice) | MH/OH/target swings, Slam-reset + parry-haste handling, OUT OF RANGE / NOT ATTACKING warnings | Our swing engine already covers MH/OH; rogue.lua consumes phase — no rogue-specific gap except the Era post-swing cue (§2.1) |

Net-new signals vs the first pass §4 watch-list: (a) **GCD ring on CP**
(Sno circular tracker); (b) **multi-CD yellow-glow state** (stacked AR/BF/
trinket/pot — one boolean off existing aura reads); (c) **short-CD row**
(Kick/Kidney/Re-stealth/Bandage — cooldown reads); (d) **MH/OH poison
reminder + charges** (new probe, Forever charges are the failure mode);
(e) **TTD input** (druid D4 EMA reuse for Rupture-vs-Eviscerate, first pass
already names it — Sno's TTD WA confirms demand); (f) **Thistle Tea item
cue** (§2.3). Everything else in the table maps onto existing five-class
patterns with no new API surface.

## 4. MUST-ANSWER (3): addon-design handoff (per-technique table)

| Technique (§2) | Signal(s) needed | Covered by existing patterns? | New probe? | CLEU shape? (oracle R1) |
|---|---|---|---|---|
| 1 SS-after-swing (Era only) | MH swing phase + 0.1–0.2s post-land window | YES — `on_bar_update` tint/glow (twist-band/SST-red-slice precedent) | No | No (swing events, not CLEU) |
| 2 tick predictor + pooling | `energy_now`, `energy_tick_in`, 65/85 bands, Combat-Potency-15 vs tick disambiguation | PARTIAL — druid D5 template; predictor math is new | YES — proc-aware tick clock (UNIT_POWER deltas) | No |
| 3 Thistle Tea cue | item count + item CD + energy-deficit gate | PARTIAL — P5/NAG consumable pattern; item probe new | YES — `GetItemCount`/`GetItemCooldown` | No |
| 4 Vanish/Overkill/MoS windows | buff presence + re-stealth CD | YES — aura + cooldown reads (P2/CD-group pattern) | No | Only if matching the Vanish CAST on `_TBC` → name-fallback table |
| 5 weapon-swap tint | swing phase at swap moment | YES — presentation on existing phase | No (macro-level; GCD cost in copy) | No |
| 6 speedrun CD point-of-no-return | boss/pull timers + 2min/5min CD states | PARTIAL — CD-group pattern; pull-timer input new | MAYBE — pull/encounter timer source TBD | No |
| 7 AR+BF stacked glow | multi-CD active boolean | YES — paladin CD-group + yellow-glow rule | No | No |
| 8 BF cleave geometry | target-count/facing sensor | NO — no lane owns it; overlaps H3/S6 target-count UNCONFIRMED | YES (risky — secret-regime limits) | No |
| Poison reminder + charges (teardown #1d) | MH/OH poison presence + charges | PARTIAL — Poisoner pattern; charges probe new | YES — charges need tooltip/probe verification | Poison PROC matching on `_TBC` → name-fallback (R1); presence via UnitAura unaffected |
| Shiv upkeep cue (first pass §3.4) | Deadly stacks + time-to-falloff + OH speed | PARTIAL — EA pre-falloff cue pattern | No (aura reads) | Shiv CAST on `_TBC` → name-fallback (R1) |

Nil-safe/toggle discipline per standing rules: Era-only cue ships
`== false`-hidden, nil = off, default documented for the options pass; NO
default-visible change without an explicit gate. Never gate on
`st.is_mainline` alone — Forever runs classic-like swing paths (swing-activity
gate); Retail stand-in keeps all rogue swing widgets inert.

## 5. Conflicts / UNCONFIRMED (recorded with evidence, none guessed)

1. WotLK SS-timing: expected TBC-like (no reset) but NO source pulled —
   UNCONFIRMED. In-client or second source required before extending §1.
2. SoD rune-instant-attacks vs swing reset (Mutilate/Saber Slash): no SoD
   source ties them to reset behavior — UNCONFIRMED.
3. Exact TBC "abilities no longer reset" engine mechanism (normalization
   patch vs per-ability flags): DESIGN INFERENCE from Sno's statement, not a
   sourced patch note — UNCONFIRMED as mechanism.
4. "This part is questionable by many pro rogues" (Warmane 455713, Wrath
   Killing-Spree OH-swap) vs Simonize swap video — RECORDED CONFLICT,
   defaults to NO swap cue on Wrath until in-client tested.
5. Vanish/Cloak per-boss immunity tables — UNCONFIRMED (Winterchill cloak
   datapoint cuts against blanket immunity).
6. Speedrun-opener deltas vs guide openers — UNCONFIRMED (no log source).
7. BF cleave positioning geometry — UNCONFIRMED.
8. Poison-charge probe shape on Forever (tooltip vs observed-count) —
   UNCONFIRMED, needs in-client check.
9. wago pack bodies (PepsiRogue config, Sno WA tunables) — unrended,
   listing/snippet text only (standing wago limitation, same as pass 1).
10. CF page bodies (NugEnergy jist, Rogue Energy Ticker, Wick's) 403 via
    fetch — listing text only; version/date claims from listings treated as
    engine-relative.

## 6. Tooling log (brief §"record every URL + what the tool returned")

Catalogs enumerated first in Code Mode: `search("firecrawl")` → full 28-tool
surface CONFIRMED (agent/status/search/scrape/parse/map/crawl/interact/
monitor/research families); `search("searxng")` → instance_info/suggestions/
web_search/web_url_read CONFIRMED. Research ran on SearxNG MCP (several
engines degraded: brave-suspended/duckduckgo-CAPTCHA/startpage-CAPTCHA noted
per-call; google-cse carried all results) + `web_url_read` extracts.
- `searxng_web_search` × 9 (SS-after-swing; Yam/PepsiRogue; weapon-swap+Nug;
  Sno-UI+vanish; Yam-BarEnergy; tbcguides-P3+openers; SS-timing-WA+Nug-body;
  AR/BF-stacking; Rod-swap+poison-tracker[degraded/empty]).
- `web_url_read` LOADED (markdown extracted, quoted in-session):
  classicroguecraft.com/swing-timing-guide (body past nav),
  tbcguides.gg/rogue-ui (two windows incl. buff/short-CD lists),
  tbcguides.gg/rogue-talents-enchants-gems (FAQ incl. swing-timing-NO),
  tbcguides.gg/rogue-p3-dps-guide (consumes/CD point-of-no-return),
  barrens.chat/viewtopic.php?t=2908 (SS-after-MH mechanism thread).
  EMPTY/BLOCKED: wago.io/1v8uT8TfF (empty after conversion — JS wall, as
  known); curseforge.com/wow/addons/wicks-poisons-and-things (403);
  wowhead.com/tbc/guide/classes/rogue/dps-addons (JS shell, snippets only).
- Firecrawl REST not needed this round (SearxNG + extracts sufficed; small
  bodies throughout).
