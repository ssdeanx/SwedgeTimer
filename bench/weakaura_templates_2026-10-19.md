# bench/weakaura_templates_2026-10-19 — popular WeakAura HUD styles as template-gallery input (RESEARCH ONLY)

Desk: weakaura-templates. Date: 2026-10-19. No addon file touched; no code.
Single NEW file (absence verified via glob before write). Companion spec:
`bench/hud_templates_2026-10-19.md` (our slot/geometry model — all mappings below
target its Core / Full+Trinkets / Minimal per-class templates and
`hud.lua` LAYOUT_KEYS: `hud_icon_size` / `hud_spacing` / `hud_orientation` /
`hud_scale` / `hud_match_bar_width` / `hud_x/y`).

Evidence bar: CONFIRMED = page/search listing actually showed it, URL cited.
UNCONFIRMED in caps otherwise. No layouts or sizes invented; no code, art, or
import strings copied (describe + link only).

Scope (operator correction 2026-10-19): TBC + Classic Era/SoD ONLY — no
WotLK/Wrath suites or styles. Wrath-only and retail-only findings from the
first pass were dropped (see §4 ledger); remaining cards map to Era/SoD +
TBC families only.

## 0. Method + tooling record

- Catalogs enumerated first via Code Mode search: firecrawl (10 tools:
  `firecrawl_search`, `firecrawl_scrape`, `firecrawl_map`, `firecrawl_agent`,
  `firecrawl_parse`, `firecrawl_crawl`, `firecrawl_monitor_*`,
  `firecrawl_find_tools`, `firecrawl_gov_search`, `firecrawl_developer_search`)
  + searxng (4 tools: `searxng_web_search`, `searxng_search_suggestions`,
  `web_url_read`, `searxng_instance_info`).
- SearXNG carried the round (6 searches, google-cse engine). Firecrawl used
  once: `firecrawl_scrape` on https://wago.io/fLyWyqQFV returned
  `"markdown":""` (1 credit) — wago.io import pages are JS apps; bodies are
  not server-rendered. `web_url_read` on https://wago.io/Afenar_Paladin likewise
  returned empty ("requires JavaScript"). All wago.io page-level claims below
  are therefore **search-listing metadata + author-site listing text**, stated
  as such — consistent with lessons.md ("SearXNG carries", "a remembered id
  is a rumor").
- One screenshot attempt: luxthos.com shaman preview image downloaded and
  viewed — it is a promo banner (game logo + "SHAMAN WEAKAURAS" title), NOT a
  UI screenshot; zero layout observable. Recorded so nobody re-tries it.
- UPDATE (operator-ordered deep round): wago.io import pages DO render via
  `firecrawl_scrape` with `waitFor: 8000` (no-wait returns the empty
  `<div id="app"></div>` shell; the "JS-walled" note above is SUPERSEDED for
  the wait-recipe). Per-attempt report:
  - https://wago.io/pzFBVUCdX no-wait → `"markdown":""` (LEN 395);
    html-format → bare app div; waitFor 8000 → full page (MDLEN 17181:
    header, stats, 11 screenshots, full Description).
  - https://wago.io/p/Dora(Benediction) + wait → full import list (used to
    enumerate the author's TBC vs WotLK items).
  - https://wago.io/dvfaXmRm8 + wait → version tag `v1.0.7WOTLK-WEAKAURA`
    (Nov-2022 series = Wrath, dropped per scope — one check, not a card).
  - https://wago.io/DZND2T3w6, /OHhIsG8F4, /hw7BD9fCn, /joURtkngg + wait →
    full headers + descriptions (MDLEN 4.5k–17k). Screenshot PNGs downloaded
    via curl and VIEWED (see §5).
  - SearXNG went rate-limited mid-round (all engines 429/CAPTCHA across
    three queries); the author-profile scrape replaced search for discovery.
- Out of scope honored except where the operator explicitly ordered
  otherwise: the §5 deep-target cards include two WOTLK items carded BY
  OPERATOR ORDER and flagged as such (gallery mapping stays Era/SoD + TBC
  only); no edits outside this file; `design/hud/options` lanes untouched.

## 1. Suite-style cards (cooldown / rotation HUDs — Era/SoD + TBC only)

### A1. Luxthos Classic Era & Hardcore line — https://wago.io/p/Luxthos
- Observed (listing text, CONFIRMED): "Luxthos Warrior WeakAuras for Classic
  Era & Hardcore" / "Luxthos Shaman WeakAuras for Classic Era & Hardcore" —
  "entirely customizable without any code or WeakAuras knowledge needed".
  (Retail TWW pages for the same author were sighted and DROPPED per scope —
  see §4.)
- Observed layout: group structure UNCONFIRMED at page-body level (JS-walled;
  no body text retrieved).
- Our-model mapping: Era-native suite from a major author = the
  visual-check target for our Core templates on Era clients (P-T1, W-T1,
  H-T1, D-T1, S-T1, R-T1 shape: single horizontal icon row, fixed size,
  match OFF). The "no-code customization" line is the UX bar our
  `hud_template` select must meet. Fit notes: spec-kit mapping is per
  class and manual; in-client side-by-side only, UNCONFIRMED until then.

### A2. Sabimaru Shaman Classic [SoD] — https://wago.io/8MyJNekEa (author page https://wago.io/p/Sabimaru)
- Observed (listing text, CONFIRMED Apr 7 2024): "Shaman Weakaura Suite —
  **Compatible with SoD and Era — Conditional Icon Loading — Rotation
  Abilities — Range/Resource Indicators — Buff/Debuff Trackers**".
- Our-model mapping (closest on-matrix match this round): Conditional Icon
  Loading ≈ our provider-hide + `hud_show_*` toggles (already shipped);
  Rotation Abilities ≈ **S-T1 Twist Core** {stormstrike, flameshock,
  earthshock, twist}; Range/Resource Indicators ≈ our `hud_range_tint` /
  `hud_mana_tint` keys (already exist — gallery copy should name them);
  Buff/Debuff Trackers ≈ **S-T2 Full Enhance + Weave** (all 8 + trinkets,
  match ON). The Rotation-vs-Trackers split is the in-scope precedent for
  our Core-vs-Full template split. Fit notes: best SoD+Era visual-check
  target for shaman found this round; SoD-vs-Era gating on our side stays
  rune/item-based per standing rule, never client-version. Body UNCONFIRMED
  (listing only).

### A3. UxkIny7oJ Rogue 2.4.3 EnergyTicker + HUD — https://wago.io/UxkIny7oJ
- Observed (snippet CONFIRMED, re-sighted from
  `bench/competitor_gaps_2026-10-19.md` §1.6): "Energybar + Ticker …
  Combo Points · Poisons (Crippling & Wound) · Actives (SnD, Rupture) ·
  CDs" — consolidated single-HUD curation on a **2.4.3 (TBC) client**, fully
  in scope.
- Our-model mapping: already our **R-T1 precedent** (hud_templates §R-T1:
  {snd, rupture, ea, tea, kick}). Energy ticker has NO slot in our contract
  (open R1 gap — still not smuggled in). Fit notes: gallery anchor for
  rogue — R-T1 copy can cite "UxkIny-style Core" naming already chosen.
  No new finding; re-confirmation only.

## 2. Swing-timer cards

### B1. Classic swing-timer search cluster — https://wago.io/search/imports/wow/classic?q=swing%20timer
- Observed (listing text, CONFIRMED): "Warrior swing timer that **turns
  yellow for heroic strike que and green for cleave que**".
- Our-model mapping: color-coded queue state = our HS-tint precedent
  (already shipped) — external demand CONFIRMED at listing level. Fit
  notes: gallery copy for W-T1 can reference queue-color reads; no new
  slot needed.

### B2. swingtimer SOD (multi-class) — https://wago.io/fLyWyqQFV
- Observed (metadata, CONFIRMED): v1.0.0 CLASSIC-WEAKAURA, tagged
  Shaman / Enhancement / Warrior / Hunter / Paladin / Rogue — one timer
  shared across five of our six classes (druid absent).
- Our-model mapping: swing bar itself (not HUD row) — precedent for our
  bars-first architecture; class coverage overlaps ours minus druid.
  Body UNCONFIRMED (scrape returned empty). Fit notes: candidate
  cross-check for swing-bar feel on SoD; in-client only.

### B3. Minimalist swing bars — https://wago.io/J8i7TTmJq, https://wago.io/AEAhYr-Nl
- Observed (listing text, CONFIRMED): "Minimalist Warrior swing bars that
  track Heroic Strike, Cleave, and Shield Block stacks" (J8i7TTmJq);
  "Simple Swing Timer (Classic 1.15.5)" tagged [1.15.6 SoD], 632 views
  (AEAhYr-Nl) — Era-version-pinned listings exist.
- Our-model mapping: minimalist precedent for our **Minimal templates**
  (P-T3/H-T3/S-T3 28px rows) + version-pinned listings support per-client
  gallery notes. Bodies UNCONFIRMED. Fit notes: none beyond precedent;
  no new slots.

### B4. TBC Anniversary Fury Swing Timer API build — https://wago.io/iSMb65pa3
- Observed (metadata, CONFIRMED): "Parsing | TBC Anniversary | Warrior |
  Swing Timer API | Classic | Fury | Swingtimer API", v1.0.12 TBC-WEAKAURA,
  "Being Rebuilt for TBC Classic".
- Our-model mapping: Anniversary API drift is real (cf. competitor_gaps
  Quagmire note) — our `compat.lua` layer is the answer; gallery needs no
  per-client template forks. Fit notes: watch item for TBC template
  verification, in-client only.

## 3. Shortlist for the template gallery (validation owner: orchestrator)

1. **R-T1 "UxkIny-style Core" — gallery anchor (no change).** Best-evidenced
   curation, on a TBC client; keep name + slot set. (A3)
2. **S-T1/S-T2 vs Sabimaru SoD suite — visual-check target.** Only
   SoD+Era-native suite found; compare our shaman rows against it
   in-client. Rotation-vs-Trackers split grounds the Core/Full story. (A2)
3. **Core rows vs Luxthos Era line — visual-check target (all classes).**
   Era-native suites from a major author; no-code-customization UX bar for
   the `hud_template` select. (A1)
4. **Minimal rows vs minimalist swing bars — precedent cite.** (B3)
5. **W-T1 copy — queue-color reads.** Yellow/green queue precedent already
   shipped as HS tint; name it in gallery copy. (B1)
6. **Shaman swing/weave visuals vs Dora's TBC Swing Timer (§D1) — borrow
   candidate.** Hand-colored swing bars (red MH / green OH) + white
   midpoint marker + Δ-seconds readout; WF ICD visualization. All
   TBC-native, all mappable to our swing + weave model. (NEW)

1. **R-T1 "UxkIny-style Core" — gallery anchor (no change).** Best-evidenced
   curation, on a TBC client; keep name + slot set. (A3)
2. **S-T1/S-T2 vs Sabimaru SoD suite — visual-check target.** Only
   SoD+Era-native suite found; compare our shaman rows against it
   in-client. Rotation-vs-Trackers split grounds the Core/Full story. (A2)
3. **Core rows vs Luxthos Era line — visual-check target (all classes).**
   Era-native suites from a major author; no-code-customization UX bar for
   the `hud_template` select. (A1)
4. **Minimal rows vs minimalist swing bars — precedent cite.** (B3)
5. **W-T1 copy — queue-color reads.** Yellow/green queue precedent already
   shipped as HS tint; name it in gallery copy. (B1)
6. **Shaman swing/weave visuals vs Dora's TBC Swing Timer (§D1) — borrow
   candidate.** Hand-colored swing bars (red MH / green OH) + white
   midpoint marker + Δ-seconds readout; WF ICD visualization. All
   TBC-native, all mappable to our swing + weave model. (NEW)
7. **Weave cast-zone bracket + per-spell tick toggles (§D3, WOTLK-flagged) —
   concept borrow, NOT kit borrow.** The "Spells start cast range zone"
   bracket + countdown + per-spell weave toggles pattern-map 1:1 onto
   `weave.lua` marker/safe-start/clip + our options shape; re-verify any
   TBC-kit assumptions before gallery copy cites them. (NEW)

## 4. Uncertainty ledger + do-not-retry list

- Pixel geometry (icon size / spacing / orientation) for the §1–§2 suites
  is UNCONFIRMED (listing-metadata only). For the §5 deep targets,
  screenshots were VIEWED and layouts are observed (stated per card).
- Do NOT re-try: no-wait wago.io scrapes (empty shell, thrice confirmed —
  use `waitFor: 8000`); luxthos.com preview PNGs (promo banners, viewed
  and confirmed content-free). SearXNG was rate-limited mid-round; the
  `wago.io/p/<author>` profile scrape replaces author search for discovery.
  Next productive step after this file is in-client side-by-side
  (TESTING.md session), not more scraping.
- Wrath/retail drops this round: Afenar TWW pages, Luxthos TWW pages,
  Luxthos COOLDOWN-MANAGER flavor (v12.1.0 retail), Warperia WotLK druid
  package, Dora's Nov-2022 "Enhance Shaman" series (verified
  `v1.0.7WOTLK-WEAKAURA` on https://wago.io/dvfaXmRm8). hw7BD9fCn and
  joURtkngg are WOTLK items carded BY OPERATOR ORDER in §5 and flagged —
  they are not gallery inputs.
- Hunter-specific cooldown-HUD suite with observable body: NOT FOUND this
  round (mNylol ElvUI BM-hunter WA is an ElvUI-profile reference, body
  UNCONFIRMED). Filed, not blocked — H-T1/H-T2 stand on rotation shape.
- Nothing copied: no import strings, no code, no assets. Links only.

## 5. Operator-targeted deep cards — Dora's TBC shaman + WOTLK-flagged comparisons

weave.lua cites used below (all CONFIRMED on disk 2026-10-19):
`get_marker_fraction` (:225), `get_safe_start_in` (:260),
`get_clip_amount` / `is_clipped` (:266/:276), `get_spark_fraction` (:301),
`get_spell_position_state` (:132, `"clip"` / `"ready"` states).

### D1. Dora's Swing Timer (TBC, IN SCOPE) — https://wago.io/OHhIsG8F4
- Header (scraped, CONFIRMED): `Dora's Swing Timer`, v1.0.3
  TBC-WEAKAURA, by [Dora(Benediction)](https://wago.io/p/Dora(Benediction)),
  Jan 30 2026 [2.5.5 TBC (Test)], tagged Shaman / Enhancement, 1 star,
  3171 views, 0 installs, 4 versions, "No custom code", "Copy import
  string" control present (import string itself NOT copied).
- Description (scraped, CONFIRMED): "Enhancement Shaman Swing Timer.
  Shows your melee swing timing with clear hand identification and
  Windfury internal cooldown tracking. Includes: live swing timer display;
  Red = Main Hand (MH); Green = Off Hand (OH); Windfury ICD visualization
  so you can see active vs dead proc windows. Built for TBC Enhancement
  where swing timing and Windfury windows directly affect DPS consistency."
  v1.0.3 note: "Added Delta Calculation to show difference between hands.
  Also made the Delta font a touch smaller" — delta readout is an
  iterated, user-facing feature, not a demo extra.
- Screenshot (VIEWED `697c20e3bd05bc34ac2e325c.png`, 360×106, CONFIRMED):
  two horizontal swing bars on a translucent dark backdrop — top bar red
  (MH), bottom bar green (OH), each draining left-to-right against a black
  track; a single vertical WHITE midpoint line spans both bars at ~55%;
  below the bars green text reads `Δ+0.12 s` (live hand-delta readout).
  Matches the operator's "red/green bars, white midpoint line,
  delta-seconds text" description exactly.
- Our-model mapping: red/green hand identification ≈ our swing-bar hand
  reads (borrow the color convention if ours differs — cheap consistency
  win); white midpoint ≈ a fixed 50%-ish reference tick (ours: marker
  fraction is COMPUTED per spell via `get_marker_fraction`, strictly more
  informative — do not regress to a fixed tick); Δ-seconds readout ≈ a
  hand-sync readout we do not surface (candidate borrow: show
  hand-delta on the swing bar; no new slot, presentation only);
  WF ICD active-vs-dead windows ≈ our weave safe/clip states
  (`get_spell_position_state` `"ready"` vs `"clip"`) rendered on the bar.
- Fit notes (TBC shaman): directly mappable, no kit risk — TBC Enhance
  kit (WF totem, SS/FS/ES shocks) is our S-T1/S-T2 kit. Borrow list:
  (1) red-MH/green-OH convention, (2) hand-delta readout, (3) WF
  ICD active-vs-dead shading on the weave marker. Have list: computed
  per-spell marker fraction, safe-start countdown math, clip verdicts.
  In-client check owed (TESTING.md session).

### D2. Dora - Enhance Shaman (WOTLK — carded BY OPERATOR ORDER, NOT a gallery input) — https://wago.io/hw7BD9fCn
- Header (scraped, CONFIRMED): `Dora - Enhance Shaman`, v1.0.24
  **WOTLK-WEAKAURA**, by Dora(Benediction), Nov 15 2022 [3.4.0 Wrath],
  tagged Shaman / Enhancement, 19 stars, 10597 views, 696 installs,
  43 comments, 25 versions, "No custom code", plays-audio flag on.
- Screenshot match (VIEWED `6324f0e80d024c68116c7dd3.png`, 346×203,
  CONFIRMED): the operator's icon-row screenshot IS this aura's
  screenshot — top row of 7 spec icons (leftmost weapon/strike icon with
  green stack-count block beneath it, then lightning / fire / earth /
  fire-elemental / lava icons, rightmost blue shield icon with `6` stack
  count); below it a thin duration bar (green fill left, WHITE midpoint
  marker, red segment, YELLOW square cap at right); bottom blue bar with
  5 MAGENTA pips (Maelstrom Weapon stacks — operator read them as black
  dots; observed color is magenta/purple on blue). Carded as the SAME aura
  per operator instruction (match, not separate).
- Our-model mapping (STRUCTURE ONLY — kit is WotLK, do not port ids):
  7-icon row ≈ our HUD single-row shape (S-T2 Full is 8 slots incl.
  trinkets — same order of magnitude, validates row density);
  stack-count-on-icon (shield `6`) ≈ stack-count text pattern worth
  borrowing for our HUD icons (presentation only, no new slot);
  MW 5-pip bar ≈ resource-pip presentation (our bars domain, not HUD —
  do not duplicate in the gallery).
- Fit notes: NO gallery mapping (WOTLK kit: Lava Burst / Hex / MW5 do
  not transfer to our Era/SoD/TBC shaman). Keep as layout-DENSITY
  reference only.

### D3. WOTLK Swingtimer cast weaving indicator (WOTLK — carded BY OPERATOR ORDER, NOT a gallery input) — https://wago.io/joURtkngg
- Header (scraped, CONFIRMED): `WOTLK Swingtimer cast weaving indicator`,
  v2.0.4-42 WOTLK-WEAKAURA, by [Ralgathor](https://wago.io/p/Ralgathor)
  (NOT Dora — authorship correction vs the "Doros" working name),
  Nov 13 2022 [3.4.0 Wrath], 34 stars, 26076 views, 2741 installs,
  53 comments, 42 versions, "No custom code", "Copy import string"
  present (not copied). Depends at runtime on the separate
  [SwingTimerAPI aura](https://wago.io/mfxY37Jl9) (sighted as link text,
  body UNCONFIRMED).
- Description (scraped, CONFIRMED): MH/OH swing timer + Synch/Stagger
  indicator; per-spell weaving ticks for Lightning Bolt, Chain Lightning,
  Lava Burst, Hex, Healing Wave, Lesser Healing Wave, Chain Heal (LvB/Hex/
  heals OFF by default, toggled in a Custom Options panel); swing-timer
  clipping indicator; GCD indicator "revamped … grey overlay on the main
  swing bar to better see when the GCD is ending related to the swing's
  state"; v2.0.4 removed green Stagger overlays ("less important in
  WOTLK") and MH/OH delta + remaining-time texts "for a cleaner swing
  bar". WA's built-in swing trigger was removed in Wrath (per official
  WA Discord, quoted on-page) — the package is an estimator over events,
  "not 100% accurate like all Swing Timer addons".
- Screenshots (VIEWED, CONFIRMED — these ARE the operator's cast-zone
  screenshots, same-aura match):
  - `636b65ec7359b87c79dc9b31.png` (208×95): bracket label "Spells start
    cast range zone" over a grey zone (left) + black bar; white midpoint
    marker; `2.4` readout; blue downward arrows marking MH and OH
    positions. Matches the operator's description exactly.
  - `636b6543808b3c5574378b37.png` (221×105): same layout mid-weave —
    `1.9` countdown, grey zone left, MH label, blue OH arrow.
  - `636b6c9be9742b7f0cb8f875.png` (208×53): tight bar crop — yellow
    cast-progress fill from left, blue MH/OH arrows, `1.9` countdown,
    green/red edge segments. Matches "countdown numbers,
    yellow/green/red bar segments".
  - `636b6889e76f06517cc95cfa.png` (444×192): the Custom Options panel —
    per-spell tick toggles (Show LB / CL / LvB / Hex / HW / LHW / CH
    ticks), Show Spells icon, Tutorial. Precedent for per-spell weave
    toggles in options UI.
  - `62f4d6ff33ceb08c738e6e40.png` (316×82): WA options group tree —
    `SwingTimerAPI` + `WeavingAPI` dependency auras listed with load
    toggles. Architecture note only.
- Our-model mapping (CONCEPT ONLY — WOTLK kit + estimator caveat):
  "cast range zone" bracket + white midpoint + countdown ↔ our
  `get_marker_fraction` (marker position) + `get_safe_start_in`
  (seconds-to-safe-start countdown) + `get_spark_fraction` (cast
  progress fill); clip indicator ↔ `is_clipped`; per-spell tick toggles
  ↔ our per-spell weave states (`get_spell_position_state`) + options
  shape; grey GCD overlay ↔ GCD-awareness in weave timing; green
  Stagger overlays (REMOVED by author in v2.0.4 as WotLK-unneeded) ↔ do
  NOT borrow — TBC has no stagger concept in our model either.
- Borrow-vs-have: BORROW (1) the "cast range zone" bracket visual
  language for our weave marker band, (2) the countdown-seconds readout
  next to the marker (`get_safe_start_in` already computes it — display
  only), (3) per-spell weave tick toggles as the options-panel shape.
  HAVE: marker fraction math, safe-start/clip verdicts, spark travel,
  MW/instant short-circuits. NEVER borrow: SwingTimerAPI estimator
  dependency (our swing state is native), WotLK spell kit, stagger UI.
  In-client check owed; TBC-kit re-verification required before any
  gallery copy cites it.

### D4. Supporting Dora TBC pieces (IN SCOPE)
- Dora's Air Totem — https://wago.io/DZND2T3w6 (TBC-WEAKAURA, 3000 views,
  scraped CONFIRMED): "complete Air Totem decision and tracking system …
  real time icon recommendation for which Air Totem to drop next,
  supports both single totem usage and Windfury based Air Totem weaving,
  and includes an optional Windfury uptime tracker for post fight
  analysis … Windfury persistence windows, swap thresholds, mana based
  suppression, and macro overrides". Maps to our **twist slot** decision
  side (WHEN to twist, not just the icon): mana-suppression and
  override concepts match our twist-gate thinking; the post-fight WF
  uptime tracker ≈ our practice-report domain (H2 precedent), not HUD.
- Dora's Swing Timer (option 3) — https://wago.io/C1wcUTmPg
  (TBC-WEAKAURA, 1217 views, profile-listing CONFIRMED): hand-delta
  variant ("Delta displays time between hands") — corroborates D1's
  delta readout as a deliberate family feature. Body UNCONFIRMED
  (not scraped — listing only, sufficient).
- Dora's TBC Enhancement Shaman Suite — https://wago.io/pzFBVUCdX
  (v1.0.31 TBC-WEAKAURA, 29 stars, 21898 views, 47 comments, 32 versions,
  scraped CONFIRMED): suite context for D1 — Shock SMART setting (auto
  Earth/Flame Shock by priority), Fire Totem TWIST setting (Searing vs
  Magma tracking with Fire Nova countdown + auto-swap), Air/Earth/Water
  totem override settings with WF 5s-pulse-aware refresh math. The suite
  is the TBC Enhance rotation in WA form; our S-T1/S-T2 slot sets
  (stormstrike/flameshock/earthshock/twist core; full + weave) cover
  the same kit. Use as the TBC shaman visual-check target alongside
  Sabimaru (SoD).

## 6. Re-verify round 2026-10-19 (upgraded firecrawl) — evidence log

Desk: weakaura-reverify. Catalogs enumerated first: firecrawl 28 tools
(`firecrawl_agent/_status/_check_crawl_status/_credit_usage/_find_tools/
_gov_search/_map/_parse/_scrape/_search/_search_feedback/_crawl/
_developer_search/_feedback/_interact/_interact_stop/_monitor_check/
_monitor_checks/_monitor_create/_monitor_delete/_monitor_get/
_monitor_list/_monitor_run/_monitor_update/_research_inspect_paper/
_research_read_paper/_research_related_papers/_research_search_papers`)
+ searxng 4 tools (`searxng_instance_info`, `searxng_search_suggestions`,
`searxng_web_search`, `web_url_read`). No camofox- or
embedding-named tool paths — the operator's camofox anti-bot +
local-transformer embeddings upgrade is server-side, not a new
surface. Recipe for every attempt below: `firecrawl_scrape` with
`waitFor: 8000` + `maxAge: 0` (the §0 wait-recipe, re-confirmed —
no-wait still returns the shell; wait returns the full page).

- https://wago.io/OHhIsG8F4 — CONFIRMED, matches §D1 exactly
  (MDLEN 3852): `Dora's Swing Timer`, v1.0.3 TBC-WEAKAURA, by
  Dora(Benediction), Jan 30 2026 [2.5.5 TBC (Test)], 1 star, 3172 views
  (D1 carded 3171 — +1 view drift, no content change), 0 installs,
  4 versions, "No custom code"; description = live swing timer, Red =
  MH, Green = OH, WF ICD active-vs-dead windows, v1.0.3 delta readout
  note. D1 stands, no correction.
- https://wago.io/hw7BD9fCn — CONFIRMED, matches §D2 exactly
  (MDLEN 12760): `Dora - Enhance Shaman`, v1.0.24 WOTLK-WEAKAURA, by
  Dora(Benediction), Nov 15 2022 [3.4.0 Wrath], 19 stars, 10597 views,
  696 installs, 43 comments, 25 versions, plays-audio, "No custom
  code"; v1.0.24 changelog = Fire Elemental Totem hardcoded-English
  fix; functions list credits Ralgathor's Swing Timer API +
  Weaving API (joURtkngg), red/green sync square, MW combo-point bar.
  SLUG VERDICT: exact slug is `hw7BD9fCn` (lowercase f — the
  dispatch's `hw7BD9F9Cn` variant 404s: "404 No results found",
  MDLEN 2438 shell only). D2 stands; WOTLK-flag-per-operator-order
  unchanged.
- https://wago.io/joURtkngg — CONFIRMED, matches §D3 exactly
  (MDLEN 12445): `WOTLK Swingtimer cast weaving indicator`,
  v2.0.4-42 WOTLK-WEAKAURA, by Ralgathor (NOT Dora — authorship
  correction holds), Nov 13 2022 [3.4.0 Wrath], 34 stars, 26076 views,
  2741 installs, 53 comments, 42 versions, "No custom code";
  v2.0.4-42 notes = per-spell weave ticks (LvB/Hex/heals, off by
  default, Custom Options panel), grey GCD overlay revamp, green
  Stagger removal, MH/OH-delta + remaining-time removal; package
  features = MH/OH swing + Synch/Stagger + weave indicators
  (LB/CL/LvB/Hex/HW/LHW/CH) + clip + GCD + SwingTimerAPI/WeavingAPI
  deps; WA-Discord estimator quote present (no native swing trigger
  in Wrath, accuracy caveat). D3 stands; WOTLK-flag unchanged.
- Screenshots were NOT re-viewed this round (prior round's VIEWED
  matches stand: D1 red/green bars + white midpoint + Δ text; D2
  icon-row match; D3 cast-zone bracket match). No new borrow/have
  changes. Next step unchanged: in-client side-by-side.
