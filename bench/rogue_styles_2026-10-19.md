# bench/rogue_styles_2026-10-19 — popular Rogue HUD/WA styles (TBC + Era/SoD ONLY) as template-gallery input

Desk: rogue-styles. Date: 2026-10-19. READ-ONLY except this NEW file (absence
verified via glob before writing — no match). No addon/test/bench edits, no
git, no code/import strings copied (describe + link only).

Scope honored: TBC + Classic Era/SoD only. Wrath/retail items excluded; where
a cited URL has drifted to a WOTLK version it is flagged and only the
TBC-era layout (via the contemporaneous guide text) feeds the gallery.

## 0. Our-model reference (all CONFIRMED on disk 2026-10-19, read-only)

- `ST.ROGUE.HUD_SLOTS` (`classes/rogue.lua:1034-1057`): snd, rupture, ea, ar,
  bf, tea, kick, kidney, restealth, bandage, coldblood, trinket1, trinket2.
- `LAYOUT_KEYS` (`hud.lua:125-129`): hud_x, hud_y, hud_scale, hud_icon_size,
  hud_match_bar_width, hud_spacing, hud_border_size, hud_border_color,
  hud_font, hud_text_size, hud_text_outline, hud_locked.
- Gallery templates (`bench/hud_templates_2026-10-19.md` §6): R-T1
  {snd, rupture, ea, tea, kick} 36/horizontal/match-OFF (recommended default);
  R-T2 +{ar, bf, trinket1/2} match-ON; R-T3 (PROVISIONAL) {kick, kidney,
  restealth, bandage, ea} 32/vertical.
- Prior corpus (not re-proven, reused): `bench/rogue_research_2026-10-19.md`,
  `bench/rogue_deep_2026-10-19.md` §§1-3, `bench/competitor_gaps_2026-10-19.md`
  §1.6/R1-R3/X2, `bench/weakaura_templates_2026-10-19.md` (A3 anchor, §3
  shortlist), `bench/hud_parity_2026-10-19.md` (R-1 GCD-swipe gap).

## 1. Method + tooling log (per brief: enumerate first, agent + extract + scrape)

- Catalogs enumerated first in Code Mode: firecrawl 10 tools shown
  (agent/status/check_crawl/credit_usage/find_tools/gov_search/map/parse/scrape/
  search + 18 more in the full 28-tool surface per prior rounds),
  searxng 4 tools (instance_info/suggestions/web_search/web_url_read).
- `searxng_web_search` × 3 (rogue WA TBC energy/CP/SnD; classic era ticker;
  anniversary cooldown tracker): **ALL ENGINES DEGRADED — zero results**
  (brave suspended, duckduckgo CAPTCHA, google-cse suspended, startpage
  CAPTCHA). SearXNG search served NOTHING this round.
- `firecrawl_agent` × 1 (multi-source rogue HUD discovery): **FAILED**
  (tool error ID c6f685e82). Agent surface unusable on this deployment.
- `firecrawl_scrape` + `waitFor: 8000` (small bodies — URL + wait only, per
  deployment discipline): **SERVED 9/9 wago pages** (full headers, stats,
  descriptions, screenshot counts). This catalog carried the round.
- `searxng web_url_read` × 3: https://www.tbcguides.gg/rogue-ui/ LOADED fully
  (whole Sno suite component list + wago URLs, quoted §2); CF nugenergy page
  → **403** (standing CF bot-wall); https://discord.gg/T9XQJw7gJj → **empty
  after conversion** (JS-wall). Discord pins UNCONFIRMED (no read possible).
- Screenshots were NOT downloaded/viewed this round (listing text + stats +
  descriptions only); pixel geometry for all cards below is UNCONFIRMED.

## 2. Style cards (ranked by in-scope popularity × gallery value)

### S1. Sno TBC rogue suite — design lineage (TBC-era layout via guide text; wago code-IDs now WOTLK-drifted)
- URLs: guide https://www.tbcguides.gg/rogue-ui/ (LOADED, full text) →
  components https://wago.io/WS4YnxEXh (CP),
  https://wago.io/0nXj3cI0s (energy),
  https://wago.io/L3XVrJdOk (actives),
  https://wago.io/95FfOT1-7 (short CDs),
  https://wago.io/Xw8J1WPRY (enemy CC), https://wago.io/4b4vAll58 (PvP HUD),
  https://wago.io/roguestats, https://wago.io/D85g6Y4CL (TTD).
- Observed (guide text, CONFIRMED): circular CP tracker with 1s-GCD ring
  (CP start red → brighter pink at 5); simple energy bar + Yam tick-corrector
  (proc-proof, "more accurate than nugenergy"); actives box + countdown
  (AR/BF/SnD/EA/Rupture/drums/haste-pot/Crusader/Mongoose/Vanish-stealth/
  Sprint/Evasion/FAP/racials/trinkets; SnD yellow-glow when CDs stacked);
  short-CD tracker (Distract/Kick/Kidney/Re-stealth/Ghostly/Bandaged);
  growing vertical enemy CC/debuff column; PvP CD HUD (fade on CD, 10s
  finish-glow + combat indicator); PvE CD bar (trinket/BF/AR/Tea/drums/
  haste-pot, grey-see-through on CD, glow off CD, hidden in BG/arena).
- Version drift (scraped, CONFIRMED): all four core IDs now serve WOTLK
  versions — WS4YnxEXh "WoTLK Combo Points + GCD Timer" v1.0.5 (30★ 30945
  views 2015 installs); 0nXj3cI0s "WoTLK Energy Bar" v1.0.9 (29★ 27706/1951,
  "removed unneeded ticker"); L3XVrJdOk "WoTLK Active Buffs" v1.0.59-59
  (45★ 40365/2710, most-viewed rogue WA seen); 95FfOT1-7 "WoTLK short CDs +
  stance tracker" v1.0.15 (12★ 10842/837, dynamic grow group, horiz/vert
  switch documented). WotLK-next-gen IDs named in descriptions (3_4x7VfZt,
  DMS3r2RGn, Cl9Q056v_, suMlTppH0) are OUT OF SCOPE, noted only.
- Our-model mapping: CP pips + GCD ring ≈ druid-D3 pips precedent; ticker ≈
  R1 energy-tick gap (Yam proc-proof rule = the spec); actives box ≈ R-T1 +
  stacked-yellow-glow (paladin CD-group pattern); short-CD tracker ≈ R-T3
  PROVISIONAL set {kick, kidney, restealth, bandage} + Ghostly (no slot —
  filed, not smuggled); PvE CD bar ≈ R-T2 {ar, bf, tea, trinkets}; TTD WA ≈
  druid-D4 EMA reuse. Geometry: horizontal icon row/box + vertical CC column
  → hud_orientation horizontal for R-T1/R-T2, vertical precedent for R-T3.
- Fit notes: the single best-in-class TBC author reference; gallery copy for
  R-T1/R-T2/R-T3 can cite per-component. In-client side-by-side still owed.

### S2. Redtuzk's Poison Tracker — most popular in-scope TBC item
- URL: https://wago.io/yTuUM1L1b (scraped, CONFIRMED: v5.2.1-13
  TBC-WEAKAURA [2.5.2], by Redtuzk, Sep 2021, 37★ 33839 views 755 installs,
  4 screenshots, no-custom-code metrics shown).
- Observed (description, CONFIRMED): MH/OH weapon-enchant abbreviated names +
  stacks + duration in a dynamic group; shows when poisons/imbuement missing
  completely; "removed stack indicator for TBC". Caveat on page (CONFIRMED):
  "created for the original TBC Classic and may not work as expected in the
  TBC Classic Anniversary."
- Our-model mapping: ≈ R2 poison-presence reminder (already shipped as text
  `classes/rogue.lua:1359-1366,1405-1424`) + Poisoner one-click MH/OH
  no-poison reminder. No slot change (presence booleans only, charges stay
  UNCONFIRMED-probe per competitor_gaps R2).
- Fit notes: highest-traction TBC-rogue WA fully in scope; Anniversary-drift
  caveat supports our compat-layer story, not a template fork.

### S3. Sinister Strike Timing — most popular Era-lineage single-purpose
- URL: https://wago.io/W4bb8CdVO (scraped, CONFIRMED: v2.0.2-4, by Redtuzk,
  May 2020 [1.13.4 Classic], 20★ 12631 views 416 installs, no custom code).
- Observed (description, CONFIRMED): icon right after MH swing to maximize
  Sword Spec/HoJ/WF procs; energy-gated (only with required energy).
- Our-model mapping: Era post-swing cue window (rogue_deep §2.1; SST red
  end-window precedent); presentation-only via `on_bar_update`, energy gate
  = 65/85 pooling bands. NO TBC mapping (REFUTED per Sno TBC FAQ — Era
  swords only).
- Fit notes: gallery anchor for the Era post-swing cue; keep out of TBC
  templates explicitly.

### S4. Holte "Classic Rogue WAs" collection — Era pack reference
- URL: https://wago.io/vcucOW5xl (scraped, CONFIRMED: collection by Holte,
  13★ 23488 views, animated-gif preview).
- Observed (description, CONFIRMED): combo bar + poison tracker left of it
  (= S2 yTuUM1L1b) + Crusader proc tracker above SnD bar (= Zg5e_hdq9).
  Layout grammar observed: tracker-left-of-bar + proc-above-bar layering.
- Our-model mapping: SnD bar ≈ R-T1 {snd}; Crusader-above-SnD ≈ proc-glow
  precedent for ar/bf stacked glow; left-of-bar poison ≈ R2 text slot.
- Fit notes: best Era pack-composition reference (layering grammar, not
  pixel values). Crusader sub-WA body UNCONFIRMED (not separately scraped).

### S5. PepsiRogue — TBC minimalist (CP + ticker + timers)
- URL: https://wago.io/1v8uT8TfF (scraped, CONFIRMED: TBC-WEAKAURA [2.5.2],
  by pepsidealer, Nov 2021, 2★ 7944 views 76 installs, 2 screenshots,
  10 versions).
- Observed (description, CONFIRMED): CP + energy-bar ticker + Crusader/SnD/
  weapon-swing timers; whole UI revealed in combat or on hostile target
  (nil-safe show rule); tick inactive until energy spent after login (Distract
  to kickstart); 5–8yd kite Intercept icon + glow + sonar ping vs warriors
  (standalone https://wago.io/gdBAe9z0s, NOT scraped — UNCONFIRMED body).
- Our-model mapping: ≈ R-T1 core {snd} + R1 ticker + swing bar; combat-reveal
  ≈ standing nil-safe show semantics; kite/sonar = PvP extras, no slots.
- Fit notes: minimalist precedent for small-screen R-T1; combat-reveal is
  already our behavior — gallery copy only.

### S6. Comfy Rogue UI [SoD] — only all-spec SoD suite found
- URL: https://wago.io/6dsez-sDj (scraped, CONFIRMED: CLASSIC-WEAKAURA
  [1.15.7 SoD], by TheComfyWizard, Jul 2025, v1.0.25, 3★ 7458 views
  17 installs, 26 versions, audio cues, 1 screenshot).
- Observed (description, CONFIRMED): all-spec SoD suite, "only showing what's
  important to a healthy rotation".
- Our-model mapping: rotation-vs-trackers split ≈ Core-vs-Full template
  story (same as Sabimaru precedent for shaman); SoD kit maps to our SoD
  rule arms (Mutilate/Envenom/Tea lines) with rune-gating, never
  client-version gating (standing rule).
- Fit notes: primary SoD visual-check target for R-T1/R-T2; body
  UNCONFIRMED (listing only) — in-client side-by-side owed.

### S7. UxkIny 2.4.3 EnergyTicker + HUD — existing gallery anchor (re-confirm)
- URL: https://wago.io/UxkIny7oJ (scraped, CONFIRMED: UNKNOWN-WEAKAURA
  version tag, by Onno, Apr 2023, 0★ 3912 views 2 installs, 1 screenshot).
- Observed (description, CONFIRMED): TBC 2.4.3 HUD — energybar + ticker
  (needs C_Timer polyfill addon + discord-hosted rar, link on page),
  CP, poisons (Crippling & Wound), actives (SnD, Rupture), CDs (BF, AR,
  Sprint, Vanish, Prem).
- Our-model mapping: already R-T1 precedent ({snd, rupture, ea, tea, kick});
  ticker = open R1 gap (no slot — not smuggled in).
- Fit notes: no change; keep "UxkIny-style Core" name. Ticker-polyfill
  detail is a cautionary precedent for our probe-free approach.

### S8. Easy Poisons — click-applier pattern (13★ Era)
- URL: https://wago.io/ohQoJB47- (scraped, CONFIRMED: CLASSIC-WEAKAURA
  [1.15.7], by Kcr003, May 2025, v1.0.1, 13★ 7285 views 29 installs,
  3 screenshots, no custom code).
- Observed (description, CONFIRMED): click / shift / ctrl / alt /
  shift-ctrl apply different poisons to MH/OH.
- Our-model mapping: applicator UX is out of swing-timer scope (Wick's
  boundary, rogue_deep #7) — gallery cites the modifier-click pattern only
  as the MH/OH-reminder interaction model for R2; no slot.
- Fit notes: pairs with S2 (tracker) + Poisoner addon (one-click + reminder)
  as the complete poison story; we own only the reminder slice.

### S9. Sharpie Era trio — swing + CP + energy-tick separates
- URLs (listing text from class page, CONFIRMED as listed): swing timer
  https://wago.io/MNMaycmml (4398 views, OH disabled by default);
  energy bar https://wago.io/Wv3KFeIt0 (2402 views, 2★, tick indicator);
  combo points https://wago.io/YeLruszqO (1875 views).
- Observed: single-purpose separates by one author (Sharpie), all Classic
  lineage, OH-swing opt-in.
- Our-model mapping: swing ≈ our bars (nothing to borrow); energy-tick ≈
  R1; CP ≈ pips. OH-disabled-by-default matches graceful-degradation ethos.
- Fit notes: precedent for Minimal templates (one widget per need); bodies
  UNCONFIRMED (not separately scraped).

### S10. SnD-uptime cluster — glow-state grammar for R-T1
- URLs (listing text, CONFIRMED as listed): TommyPickleJuice SnD tracker
  https://wago.io/Y4fnGp33g (1056 views: in-combat only, glow when MISSING,
  timer when active, RED glow when expiring); Dershowitz's SnD
  https://wago.io/-7sYrKJfv (446 views); SnD blurting sound reminder
  https://wago.io/pKqUO1tSE (2571 views, needs LittleWigs/BigWigs for sound);
  Airfoil SnD+CP+Energy minimalist https://wago.io/dOTQ7JwQU (scraped,
  CONFIRMED: CLASSIC-WEAKAURA [1.15.2 SoD], Jun 2024, 0★ 1279 views
  1 install — "minimalist icon for SnD timer, combo points and energy").
- Our-model mapping: missing-glow / expiring-red / active-timer ≈ aura-slot
  glow states (`rogue.lua:1087-1091` ROGUE_HUD_GLOW_SECONDS) — grammar
  match, no new slot; sound reminder ≈ practice-drill cue surface, not HUD.
- Fit notes: the missing→active→expiring tri-state is THE gallery grammar
  for R-T1 snd/rupture copy.

### S11. Era packs — Gambitz / Roflmiau / Lebowsky (spec-switch + styling)
- URLs (listing text, CONFIRMED as listed): Gambitz
  https://wago.io/8UlzimYZ0 (6499 views, 1★, PvE/PvP spec-switch, trinkets by
  equipped, racial icon); Roflmiau https://wago.io/LYgmRw91k (3399 views,
  5★, Masque-styled); Lebowsky pack https://wago.io/WwzRPKY9p (1569 views).
- Our-model mapping: spec-switch ≈ family-conditional slot sets (warrior
  precedent; rogue SoD-vs-Era rule arms); trinkets-by-equipped ≈ graceful
  trinket-hide (already shipped); Masque circles ≈ Sno's Raeli-ring SnD note
  (S1) — skin layer, not our contract.
- Fit notes: styling/conditional-loading references only; bodies
  UNCONFIRMED (not separately scraped).

### S12. Rogue Resources (Solessfir) — newest Era design ideas
- URL: https://wago.io/n81Q6Grr3 (listing text, CONFIRMED as listed: Sep
  2026, 271 views — minimal energy + CP tracker with colors/gradients/
  animations, energy ticks, GCD tracking, ability-cost thresholds, overcap
  warning).
- Our-model mapping: cost thresholds + overcap warning ≈ pooling-band tint
  (65/85) presentation ideas for R1; GCD tracking ≈ R-1 GCD-borrow rule
  (hud_parity §6) — external demand for the exact gap filed.
- Fit notes: watch item (newest); body UNCONFIRMED. Strengthens R-1/R1
  priority, nothing new to spec.

### S13. swingtimer SOD — cross-class SoD precedent (low traction)
- URL: https://wago.io/fLyWyqQFV (scraped, CONFIRMED: CLASSIC-WEAKAURA
  [1.15.1 SoD], by google, Feb 2024, 2★ 1776 views 1 install, animated-gif
  preview; page exposes full aura table — import string NOT copied).
- Observed: thin swing bar anchored to PlayerFrameManaBar; tags cover
  Shaman/Warrior/Hunter/Paladin/Rogue (druid absent).
- Our-model mapping: bars-first architecture precedent (not HUD row); rogue
  is a covered class, no rogue-specific signal.
- Fit notes: cross-check target for swing feel on SoD only; low traction
  (1776 views) — cite, don't chase.

### S14. Boundary items (not gallery inputs — recorded so nobody re-tries)
- Poison Reminder https://wago.io/VMZJTaQ4z (284 views) + Pippo poison buyer
  https://wago.io/BTTUvrrT3 (941 views, 4★): buying/crafting helpers —
  out of swing-timer scope (Wick's boundary).
- Rogue Energy Ticks https://wago.io/0m9rLEr1E (1194 views, 1★) + Rogue CDs
  https://wago.io/NASRim-5N (459 views) + Sharpie raid-buff reminder
  -xt48wB1x + Pilsung hardcore 4viXEDIa3 + Darkmantle proc 0fpUElcvj (1152):
  listing-level only, no design detail beyond their one-line descriptions.
- Comfy SoD consumable inventory https://wago.io/vPZxHf4qU (4429 views):
  consume-list WA — practice/report surface, not HUD.
- CF NugEnergy / Rogue Energy Ticker / BarEnergy-TBC: re-cite rogue_deep
  §2.2 (CF listing text CONFIRMED there); live re-read ATTEMPTED this round
  → 403 bot-wall (UNCONFIRMED live, standing limitation).
- Class Discord pins (Ravenholdt / Sno's discord): ATTEMPTED via
  web_url_read on invite → empty after conversion (JS-wall). UNCONFIRMED —
  needs a logged-in client, not more scraping.
- Standalone "Yam's Rogue Energy Tick Overlay" wago URL: NOT isolated this
  round (SearXNG search down, no wago-search scrape attempted — search pages
  are best-match soup, §3). Yam's code is observable packaged inside Sno's
  TBC suite (guide credit, §S1). UNCONFIRMED as a standalone import.

## 3. Shortlist for the template gallery (validation owner: orchestrator)

1. **R-T1 "UxkIny-style Core" — anchor, no change** (S7). Best-evidenced
   TBC curation; ticker stays R1-gap, not smuggled in.
2. **Sno TBC component grammar — primary design reference** (S1): circular
   CP + GCD ring, Yam proc-proof ticker, actives box + SnD multi-glow,
   dynamic short-CD group, PvE CD bar. Cite per-component; flag WOTLK drift
   on the four code-IDs so nobody imports them for Anniversary.
3. **Redtuzk Poison Tracker — MH/OH reminder model** (S2): abbreviated
   names + stacks + duration + missing-state; Anniversary caveat noted.
4. **Era cue grammar — post-swing icon + SnD tri-state** (S3 + S10):
   energy-gated post-MH icon (Era only); missing-glow / active-timer /
   expiring-red for snd/rupture glow copy.
5. **SoD visual-check target — Comfy suite** (S6): all-spec rotation-focused;
   in-client side-by-side owed.
6. **Minimal precedent — Sharpie separates + dOTQ7JwQU** (S9 + S10):
   one-widget-per-need; supports Minimal-template story.
7. **New-idea watch — Rogue Resources thresholds/overcap** (S12):
   strengthens R-1/R1; no new spec.

## 4. Uncertainty ledger + do-not-retry list

- Pixel geometry (icon size/spacing/orientation) for every card is
  UNCONFIRMED (listing/description text only; no screenshots viewed this
  round — the wago screenshot PNG URLs are on the bench above for an
  in-client or image-view round, not re-scraped).
- Bodies (import strings, custom code): never pulled, never copied — all
  claims are header/description/listing-level.
- Popularity = page stars/views/installs as scraped 2026-10-19 (wago
  best-match order is NOT a popularity sort; the TBC class URL served
  CLASSIC-tagged items under best-match — recorded exactly as seen).
- Do NOT re-try: SearXNG web_search while all engines suspended (3×
  degraded this round); firecrawl_agent (hard failure c6f685e8);
  firecrawl_search/developer_search (known-broken per lessons.md);
  no-wait wago scrapes (empty shell — waitFor:8000 recipe CONFIRMED 9/9);
  CF file/main pages via web_url_read (403 standing wall); discord invites
  via web_url_read (JS-wall, needs login).
- Next productive step: in-client side-by-side (TESTING.md session) of
  R-T1/R-T2 against S1/S2/S6, not more scraping.
