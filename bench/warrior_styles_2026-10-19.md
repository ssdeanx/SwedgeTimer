# bench/warrior_styles_2026-10-19 — popular Warrior HUD / swing-timer styles (TBC + Classic Era/SoD ONLY)

Desk: warrior-styles. Date: 2026-10-19. READ-ONLY except this NEW file
(absence verified via glob `warrior_styles_2026-10-19.md` in bench/ before
write — no match). No addon/test/bench edits; no code, art, or import
strings copied (describe + link only). No Wrath/WOTLK or retail styles carded.

Our-model reference (READ-ONLY, no code touched):
- `classes/warrior.lua:2950-2957` load-time sets + `resolve_guide_slots`
  `:2965-2989`: TBC/Era-base `{op, execute, slam, hs, bt, ww, trinket1,
  trinket2}`; SoD (Era+rune) `{execute, slam, hs, bt, ww, raging_blow,
  trinket1, trinket2}`; default/Forever branch `{op, execute, slam, hs,
  cleave, hamstring, trinket1, trinket2}`. (Wrath-arms set exists in the
  same function — OUT OF SCOPE, not mapped below.)
- `hud.lua:125-129` LAYOUT_KEYS: `hud_x/y/scale/icon_size/match_bar_width/
  spacing/orientation/border_size/border_color/font/text_size/text_outline/
  locked`. All geometry below uses ONLY these keys.
- Companion specs: `bench/hud_templates_2026-10-19.md` (W-T1/W-T2/W-T3),
  `bench/weakaura_templates_2026-10-19.md` (A/B/D cards — extended, never
  re-derived here), `bench/competitor_gaps_2026-10-19.md` (W1/W2).

Evidence bar: CONFIRMED = scraped page text or VIEWED screenshot, URL
cited. UNCONFIRMED in caps otherwise. Per-attempt record in §5.

## 0. Method + tooling record

- Catalogs enumerated first in Code Mode: `search({query:"firecrawl"})` →
  10-item surface CONFIRMED on THIS deployment (`firecrawl_agent`,
  `_agent_status`, `_check_crawl_status`, `_credit_usage`, `_find_tools`,
  `_gov_search`, `_map`, `_parse`, `_scrape`, `_search`). The "28-tool"
  count in lessons.md includes monitor/research families visible on a
  fuller deployment — not present here. `search({query:"searxng"})` → 4
  tools CONFIRMED (`searxng_instance_info`, `searxng_search_suggestions`,
  `searxng_web_search`, `web_url_read`). No camofox- or embedding-named
  tool paths — the operator's camofox anti-bot + local-transformer
  embeddings upgrade is server-side, not a new surface (matches
  weakaura_templates §6).
- Request bodies kept to `{url, waitFor: 8000}` or smaller throughout
  (operator discipline: invalid bodies are rejected on this deployment).
- Served this round: `firecrawl_scrape` (6 page scrapes, all wago.io
  import pages with `waitFor: 8000` — the §0 wait-recipe, re-confirmed).
  SearXNG served NOTHING (see §5). Screenshots downloaded via curl and
  VIEWED (§5).

## 1. Ranked style cards (in-scope clients only)

Rank = in-scope popularity (installs/views/stars where the page shows
them) × template relevance. All headers/descriptions scraped CONFIRMED
via `firecrawl_scrape` + `waitFor: 8000` unless noted.

### W1. Aurokin — Buff Battle / Commanding Shout tracker — https://wago.io/HFvEcUnu4
- Header (CONFIRMED): `Buff Battle Shout / Commanding Shout`, v1.0.8
  TBC-WEAKAURA, by Aurokin, Mar 3 2022 [2.5.3 TBC], 30 stars, 39949 views,
  1934 installs, "No custom code". Most-installed warrior item in scope.
- Description (CONFIRMED): "This WeakAura tells you when someone in your
  party does not have battle shout / commanding shout … It also tells you
  who needs battle shout / commanding shout. It defaults to Battle Shout
  but if you cast Commanding Shout then it tracks Commanding Shout
  instead." Plus: range-check feature + per-class enable/disable in
  custom options. Caveat on-page: "created for the original TBC Classic
  and may not work as expected in the TBC Classic Anniversary."
- Observed layout: party-list text readout (who-needs-shout names), NOT an
  icon row or bar. Screenshot not viewed (single PNG sighted in markup,
  not downloaded — layout taken from description prose).
- Our-model mapping: NO HUD slot — shout upkeep is buff coverage, not a
  rotation icon. Maps to banked W2 (Battle/Commanding-shout reminder,
  competitor_gaps §W2) and our shipped Battle Shout badge — not to any
  W-T* template slot set.
- Fit notes: gallery precedent for "shout reminder" copy if W2 builds;
  per-class toggles + range check = options-shape precedent (nil-safe
  opt-ins, existing standing rule). Anniversary caveat mirrors our
  compat-layer answer — no per-client template fork needed.

### W2. AcidBomb — TBC Fury Swing Timer + Rage Bar API build — https://wago.io/iSMb65pa3
- Header (CONFIRMED): `Parsing | TBC Anniversary | Warrior | Swing Timer
  API | Classic | Fury | Swingtimer API |`, v1.0.12 TBC-WEAKAURA, by
  AcidBomb, Apr 30 2026 [2.5.5 TBC (Test)], 6 stars, 6831 views,
  19 installs, tagged Fury/Arms/Protection (+Shaman/Hunter), "No custom
  code", 13 versions, 24 comments. "Being Rebuilt for TBC Classic."
- Description (CONFIRMED): "This is my warrior Swing Timers and Rage Bar.
  Swing Timers are perfect for Heroic Strike Cancel and Rage bar changes
  color with rage and also highlights amount of rage Heroic Strike will
  use when it is queued. These are meant for top tier parsing." Plus:
  custom SwingTimerAPI "adjust your swingtimer based on latency and your
  haste rating", "removed over 80 lines" perf pass.
- Observed layout (screenshot VIEWED `acid1.gif`, 641×360 crop): THREE
  stacked horizontal bars — top bar YELLOW fill on black track (HS-queued
  state); middle dark bar with small peach segment at left; bottom
  RED/pink rage bar with a YELLOW tick marker and white `40` rage-number
  text. Action-button icon row above, more buttons below. Matches the
  "rage bar changes color / highlights HS-queue amount" description.
- Our-model mapping: bars domain (swing bar + rage bar), NOT the HUD
  icon row. HS-queue color = our HS-tint precedent, independently
  CONFIRMED here at screenshot level (yellow queue state). Rage-number
  `40` text = presentation our bars do not show (borrow candidate, text
  only — no new slot). Latency/haste-adjusted timer ≈ our deadzone +
  sync work (cite, don't duplicate).
- Fit notes: strongest in-scope "parse-grade fury" visual anchor. W-T1
  {op, execute, bt, ww, hs} stays the template core — this page confirms
  the fury kit (HS-cancel + rage awareness) is the thing templates must
  serve. Borrow list: (1) rage-amount number on the bar, (2) queue-amount
  highlight segment. In-client side-by-side owed (TESTING.md session).

### W3. ombre — Simple Warrior Swing Timers (queue colors + Sunder) — https://wago.io/J8i7TTmJq
- Header (CONFIRMED): `Simple Warrior Swing Timers`, v1.0.1
  UNKNOWN-WEAKAURA (Era item, predates flavor tags), by ombre, Jul 20
  2020 [1.13.5 Classic], 5 stars, 3915 views, 276 installs, "No custom
  code".
- Description (CONFIRMED, in full): "Minimalist Warrior swing bars that
  track Heroic Strike, Cleave, and Shield Block stacks, based on the type
  of weapon you have equipped. Also uses seperate bars to track the
  current stacks + remaining duration of Sunder Armor on your target."
  Features: "One bar for wielding a Two-Hander, and two bars when dual
  wielding, or when wielding a shield and a one hand weapon. When a
  shield is equipped, OH bar changes it's colorr/fill, to show your
  current Shield Block stacks. Changes color of weapon bars when Cleave
  (Minty Green) or Heroic Strike (Yellow) are queued, or Shield Block
  (Blue) stacks are active."
- Observed layout (screenshot VIEWED `ombre1.gif` first frame, 156×29):
  single thin horizontal minimalist bar — light-grey fill segment left
  on black track, over a dark-red game-world backdrop. One bar = 2H
  configuration per the description. Queue-color states described in
  prose, not observed (static frame, unqueued).
- Our-model mapping: bars domain again. Queue colors CONFIRM external
  demand for exactly what we ship: HS-yellow ≈ our HS tint; Cleave
  mint-green ≈ our cleave tint `{64,130,7}` (same yellow-green hue
  family — warrior lane kept default with icon citation; gallery copy
  can name the shared convention). Shield-Block blue ≈ our Shield Block
  bar. Sunder stack/duration bars = debuff-bar domain — NO slot in our
  HUD contract, not proposed.
- Fit notes: minimalist precedent for W-T-adjacent bars copy + the
  1-bar-2H / 2-bar-DW rule (our bars already branch on setup). Arms/tank
  note: shield-equipped OH recolor supports keeping shield/SB reads on
  the bars rather than inventing HUD slots for them.

### W4. Krickerl — Simple Swing Timer, SoD-version-pinned — https://wago.io/AEAhYr-Nl
- Header (CONFIRMED): `Simple Swing Timer (Classic 1.15.5)`, v1.0.0
  CLASSIC-WEAKAURA, by Krickerl, Feb 15 2025 [1.15.6 SoD], 0 stars,
  634 views, 0 installs, tagged Warrior/Shaman/Rogue/Priest/Paladin
  (+6 more classes).
- Observed layout: UNCONFIRMED — page body below the header is the WA
  export table (JSON), no prose description, no screenshot sighted in
  markup. Title + SoD version tag are the entire observable.
- Our-model mapping: multi-class shared swing timer = bars-first
  architecture precedent (one timer, five+ of our six classes — druid
  absent here, same gap as the SOD timer below).
- Fit notes: precedent cite only (SoD-version-pinned listings exist →
  per-client gallery notes are legitimate). No slot, no borrow.

### W5. google — swingtimer SOD (five-class shared timer) — https://wago.io/fLyWyqQFV
- Header (CONFIRMED): `swingtimer SOD`, v1.0.0 CLASSIC-WEAKAURA, by
  google, Feb 18 2024 [1.15.1 SoD], 2 stars, 1776 views, 1 install,
  tagged Shaman/Enhancement/Warrior/Hunter/Paladin (+1 more = Rogue per
  prior round). Single screenshot sighted in markup, not downloaded
  (prior round scraped empty without wait; this round header confirmed,
  body still export-table only).
- Observed layout: UNCONFIRMED (no prose body retrieved either round;
  prior card weakaura_templates §B2 stands).
- Our-model mapping: same as W4 — shared-timer precedent overlapping
  our class coverage minus druid.
- Fit notes: cross-check candidate for swing-bar feel on SoD, in-client
  only. Nothing citable beyond the header.

### W6. Anker64 — [AQS] Desync Alert (TBC, code-level) — https://wago.io/jFIL_JaSw
- Header (CONFIRMED): `[AQS] Desync Alert (TBC)`, v1.0.0 TBC-WEAKAURA, by
  Anker64, Jun 9 2026 [2.5.5 TBC (Test)], 0 stars, 492 views, 0 installs.
- Observed layout: UNCONFIRMED as prose — page body is the WA export
  table (JSON). Observable from the code table: custom Lua binding
  `LibClassicSwingTimerAPI` (with `-1.0` fallback), `OnDelta` swing-delta
  callback driving `WeakAuras.ScanEvents`, glow show/hide finish actions
  (`do_glow`/`glow_action: hide`). So: a desync EVENT + GLOW
  presentation, no icon row, no bar text described.
- Our-model mapping: demand-CONFIRM at code level for banked W1
  (desync indicator, competitor_gaps §W1; warrior-desync lane BUILT the
  spark). Glow presentation ≈ our offhand-spark-tint approach (same
  visual family, different mechanism — ours is native swing state, theirs
  is a LibClassicSwingTimerAPI estimator; NEVER borrow the dependency).
- Fit notes: keep as W1-demand citation. No template mapping (desync is
  a bar-spark read, not a HUD slot).

### W7. Classic swing-timer search cluster (queue-color convention) — listing-level
- Source: `bench/weakaura_templates_2026-10-19.md` §B1 (re-sighted, not
  re-scraped — no re-searching answered questions): "Warrior swing timer
  that turns yellow for heroic strike que and green for cleave que"
  (https://wago.io/search/imports/wow/classic?q=swing%20timer, listing
  text CONFIRMED prior round).
- Our-model mapping: the yellow-HS / green-Cleave convention, now
  triple-sourced (cluster + ombre W3 + AcidBomb W2 screenshot). Our
  shipped tints (HS red-peak, Cleave `{64,130,7}` icon-hue green) sit
  inside this convention — gallery copy for W-T1 can name it.
- Fit notes: naming only. No new slot.

## 2. Deliberately NOT carded (scope fence)

- Afenar-style suites: NO retrievable Classic/TBC warrior line this
  round — https://wago.io/p/Afenar via `firecrawl_scrape`+wait returned
  nav shell only (filter for warrior/classic/tbc/burning/crusade/season/
  discovery matched chrome links, zero pack rows); `web_url_read` on the
  same URL returned EMPTY ("requires JavaScript", §5). Prior round
  established Afenar pages as retail/TWW and dropped them per scope.
  "Afenar-style" remains a LAYOUT reference (icon row + cooldown
  swipes) with classic applicability UNCONFIRMED — not a ranked card.
- Wrath-only / retail-only suites: excluded per scope (same fence as
  weakaura_templates §4; Dora Nov-2022 Wrath series stays out).
- Fight Club / class-lounge Discord pins: not fetchable with available
  tools (no Discord surface in either catalog) — UNCONFIRMED, recorded
  so nobody re-tries blind. In-client community check belongs to the
  TESTING.md session, not scraping.
- Wowhead TBC warrior addons guide: fetch attempted (§5), body not
  recovered; the "swing timer is essential / remain out of sync" snippet
  stays banked in competitor_gaps §W1 — cited by reference, not
  re-derived.

## 3. Shortlist for the template gallery (validation owner: orchestrator)

1. **W-T1 "Fury Core" stays the default {op, execute, bt, ww, hs}, 36 /
   horizontal / match OFF.** AcidBomb W2 (parse-grade fury, 6.8k views)
   + ombre W3 (Era minimalist, 276 installs) agree the fury kit is the
   core. Gallery copy names the triple-sourced convention: "HS queues
   yellow, Cleave queues green" (W2 screenshot + W3 prose + W7 cluster).
2. **W-T2 "Full + Trinkets" (family-full + trinket1/2, match ON) stays.**
   No new evidence for or against; trinket/ICD demand rests on the
   Fojji/three-implementation cite already banked (competitor_gaps §S1/X1,
   by reference).
3. **W-T3 "Arms / SoD" (family-conditional) stays PROVISIONAL.** ombre's
   shield-equipped OH recolor (W3) supports keeping SB/shield reads on
   the bars; nothing found that promotes tank/arms reads into HUD slots.
4. **Borrow candidate (bars, text only): rage-amount number.** AcidBomb
   screenshot shows white `40` on the rage bar (VIEWED). Our bars show
   no numeric rage — display-only addition, no new slot, options-gated
   per standing rules. Build lane decides; in-client check first.
5. **Borrow candidate (bars, presentation only): queue-amount highlight.**
   AcidBomb "highlights amount of rage Heroic Strike will use when
   queued" (description CONFIRMED, segment visible in screenshot). Same
   shape as our tint — highlight-vs-tint is the design decision, owed to
   the bars lane.
6. **NOT borrowed:** SwingTimerAPI estimator dependency (ours is native
   swing state); Sunder stack bars (debuff-bar domain, no HUD slot);
   AQS glow mechanism (ours shipped native); shout-tracker UI (W2-banked
   engine work, not a template); Afenar retail kits (out of scope).

## 4. Uncertainty ledger

- Pixel geometry (icon size / spacing / orientation) for W1–W6:
  UNCONFIRMED throughout — pages give prose + counts, not CSS. Our
  geometry stays on LAYOUT_KEYS defaults until in-client side-by-side.
- W4/W5 bodies are export-table JSON (no prose, no viewed screenshot);
  W6 layout is code-table inference (event + glow), not an observed UI.
  All three stay low-rank for exactly this reason.
- Screenshot frames: ombre first-frame only (GIF not scrubbed);
  AcidBomb single crop VIEWED as served. Queue-color *states* observed
  only on AcidBomb (yellow top bar); ombre's yellow/green/blue states
  are prose-described, not pixel-observed.
- In-client readability + Anniversary drift (Aurokin's own caveat on W1)
  UNCONFIRMED — owed to the TESTING.md session, not more scraping.

## 5. Per-attempt evidence log (failed = wall recorded, entry UNCONFIRMED)

Tool discipline: every firecrawl body ≤ `{url, waitFor: 8000}` (operator
order — invalid bodies rejected on this deployment).

| # | Tool + target | What the page/tool actually returned |
|---|---|---|
| 1 | Code-Mode `search({query:"firecrawl"})` | 10-tool surface CONFIRMED (list in §0). No camofox/embedding names — server-side. |
| 2 | Code-Mode `search({query:"searxng"})` | 4 tools CONFIRMED (list in §0). |
| 3 | `searxng_instance_info` + `searxng_search_suggestions("warrior swing timer wago TBC")` | Instance reachable (http://0.0.0.0:8069); suggestions returned (truncated). SearXNG up at infra level. |
| 4 | `searxng_web_search("wago warrior swing timer TBC heroic strike queue")` | WALL: zero results, engines brave/duckduckgo/google-cse/startpage all suspended/CAPTCHA. Served NOTHING. |
| 5 | `firecrawl_search` (developer query) | WALL: "Invalid request body" — same failure as lessons.md. Served NOTHING. |
| 6 | `firecrawl_scrape https://wago.io/iSMb65pa3` + wait | FULL page (header/stats/description/screenshots) — W2 card. Served. |
| 7 | `firecrawl_scrape https://wago.io/J8i7TTmJq` + wait | FULL page (5★ Era item, full description) — W3 card. Served. |
| 8 | `firecrawl_scrape https://wago.io/AEAhYr-Nl` + wait | Header CONFIRMED (SoD 1.15.6, 634 views); body = export JSON — W4 card. Served. |
| 9 | `firecrawl_scrape https://wago.io/fLyWyqQFV` + wait | Header CONFIRMED (SoD 1.15.1, 1776 views); body = export table — W5 card. Served. |
| 10 | `firecrawl_scrape https://wago.io/HFvEcUnu4` + wait (×2, header + description slices) | FULL header + description (30★/1934 installs, shout logic, Anniversary caveat) — W1 card. Served. |
| 11 | `firecrawl_scrape https://wago.io/jFIL_JaSw` + wait | Header + code table (LibClassicSwingTimerAPI bind, glow actions) — W6 card. Served. |
| 12 | `firecrawl_map https://wago.io/tbc-weakauras/classes/warrior` | Returned `{"links":[],"id":"01a15588-…"}`; `firecrawl_check_crawl_status` on that id → **404**. Discovery via map DEAD on this deployment. Recorded, not retried. |
| 13 | `searxng_web_search("wago warrior weakaura TBC fury")` (retry) | WALL again (same 4 engines). SearXNG served NOTHING all round. |
| 14 | `firecrawl_scrape https://wago.io/p/Afenar` + wait + keyword filter | Nav shell only, zero pack rows — Afenar classic line UNCONFIRMED (§2). Served (negative result). |
| 15 | `web_url_read https://wago.io/p/Afenar` | WALL: "empty after conversion … requires JavaScript." Served NOTHING. |
| 16 | `web_url_read https://www.wowhead.com/tbc/guide/classes/warrior/dps-addons` | Page chrome only (guide body behind JS/tabs) — header CONFIRMS Beanna guide, updated 2026/02/10, Patch 2.5.6. Body UNCONFIRMED via this path; snippet cite stands by reference. Partial. |
| 17 | curl media.wago.io screenshots (ombre gif 385KB, acid gif 2.9MB) → viewed | ombre: single dark minimalist bar w/ grey fill (VIEWED). AcidBomb: 3 stacked bars, yellow queue bar, red rage bar w/ `40` (VIEWED). Served. Files: `/tmp/opencode/wstyle/ombre1.gif`, `acid1.gif`. |
