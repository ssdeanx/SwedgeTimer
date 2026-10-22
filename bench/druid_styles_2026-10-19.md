# bench/druid_styles_2026-10-19 — popular feral Druid HUD/WeakAura styles (TBC + Classic Era/SoD ONLY)

Desk: druid-styles (subagent, READ-ONLY). Date: 2026-10-19. No addon/test file touched.
Single NEW file (absence verified via glob `bench/druid_styles_2026-10-19.md` before write — no match).
No code, art, or import strings copied (describe + link only).

Scope (operator): TBC + Classic Era/SoD ONLY — no Wrath/WOTLK, no retail, no Cata/Mists.
Wrath-only and Cata-only findings sighted during the round were dropped (see §4 ledger).

## 0. Our model (read-only reference, CONFIRMED on disk this session)

- `ST.DRUID.HUD_SLOTS`, `classes/druid.lua:1972-1984` (11 slots): maul, mangle,
  rip, rake, bite, shred, claw, tf (Tiger's Fury 9845), berserk (50334),
  trinket1 (inv 13), trinket2 (inv 14). TF/Berserk provider-hide without spell
  data; rotational seven show the GCD swipe + mana/range tints; queued Maul
  greys the maul slot.
- `LAYOUT_KEYS`, `hud.lua:125-129`: `hud_x`, `hud_y`, `hud_scale`,
  `hud_icon_size`, `hud_match_bar_width`, `hud_spacing`, `hud_orientation`,
  `hud_border_size`, `hud_border_color`, `hud_font`, `hud_text_size`,
  `hud_outline`, `hud_locked`. Templates use these keys only.
- Gallery targets, `bench/hud_templates_2026-10-19.md` §4: **D-T1 "Bleed Core"**
  {mangle, rip, rake, shred} 36/horiz/match-off; **D-T2 "Full Feral + Pops"**
  all-visible match-ON; **D-T3 "Bear Guard"** {maul, mangle, berserk, trinkets} 32.
- Honest boundary: our HUD is a single icon row; WA energy/CP/resource BARS map
  to our swing/tick-bar domain (`bars.lua` + `druid_energy.lua`), NOT to HUD
  slots. Cards below say which side each WA element maps to.

## 0b. Method + tooling record (request-body discipline observed)

- Catalogs enumerated first via Code Mode search: firecrawl 28 tools + searxng
  4 tools. No camofox- or embedding-named tool paths — the upgrade is
  server-side, not a new surface.
- `firecrawl_agent` (prompt + maxCredits body) → REJECTED
  (`f72cd27a7cf94c3bb39e1e8216549194`); recorded, fell back per protocol.
- `firecrawl_search` → invalid request body (known deployment quirk, matches
  bench/lessons.md); fell back to SearXNG + `default.websearch`.
- SearXNG `searxng_web_search` → rate-limited Degraded on 3 druid queries
  (brave/du­ckduckgo/google-cse/startpage 429/CAPTCHA); `default.websearch`
  carried discovery (wago.io feral queries, snippets CONFIRMED as listing text).
- `firecrawl_scrape` with SMALL bodies only (URL alone, or URL + `waitFor: 8000`):
  no-wait returns the bare `<div id="app">` shell (LEN ~395, thrice confirmed);
  wait-recipe returns the full page (MDLEN 4.8k–12k). Every wago.io page claim
  below is a waited scrape unless stated otherwise. Serving catalog per attempt
  is stated (§3).
- Screenshots: 3 PNGs curl-downloaded to `/tmp/opencode/druidstyles/` and VIEWED
  (Sabimaru, Meatslab, Ryecoke); Luxthos Era GIF downloaded (6.2 MB) but NOT
  viewed (layout from description text only — stated per card).

## 1. Ranked style cards (all in-scope: CLASSIC-WEAKAURA or TBC-WEAKAURA only)

### D1. Sabimaru - Druid Classic [SoD] — https://wago.io/bQynAWaKe
- Header (waited scrape, CONFIRMED): `Sabimaru - Druid Classic [SoD]`,
  v1.5.8-45 CLASSIC-WEAKAURA, by Sabimaru, Apr 19 2024 [1.15.2 SoD],
  **38 stars / 25116 views / 358 installs**, 42 comments, 45 versions,
  "No custom code". Strongest SoD/Era suite found this round by installs.
- Description (CONFIRMED): "Compatible with SoD and Era — Conditional Icon
  Loading — Rotation Abilities — Range/Resource Indicators — Buff/Debuff
  Trackers with Stack Counters — Eclipse/Combo Point/Energy/Rage Bars —
  Mana Bar with 5s Rule — Swing Timer — Cooldowns. You can re-order core
  abilities by dragging within their grouping. Anything past the 7th active
  slot will be hidden!"
- Screenshot (VIEWED `65ecdfe2d3281917272f46d6.png`, 375×159, CONFIRMED): top
  row of 4 ability icons with stack/count overlays (45, 2, claws, 4); below a
  segmented green energy bar + yellow/blue resource bars with a `31` readout;
  bottom pair of small icons with counts (5, 42). Matches the
  icon-row + resource-bars + stack-counter description exactly.
- Observed layout: reorderable core-ability icon row (7-active cap) + CP/energy/
  rage bars + mana-with-5s-rule bar + swing timer + buff/debuff trackers with
  stack counters.
- Our-model mapping: icon row ≈ **D-T2 Full Feral** (all-slots row, match-ON
  rhythm); Conditional Icon Loading ≈ our provider-hide + `hud_show_*`
  toggles (already shipped); Range/Resource Indicators ≈ our `hud_range_tint` /
  `hud_mana_tint` keys (already shipped — gallery copy should name them);
  CP/energy/rage/mana bars + swing timer ≈ our bars/tick domain (NOT HUD
  slots — do not duplicate); 7-active cap ≈ our visible-subset curation story.
- Fit notes: best SoD+Era visual-check target for druid; compare D-T1/D-T2 rows
  against it in-client. SoD-vs-Era gating on our side stays rune/item-based per
  standing rule, never client-version.

### D2. Ryecoke's TBC Druid Auras — https://wago.io/36c1KstPG
- Header (waited scrape, CONFIRMED): `Ryecoke's TBC Druid Auras`, v1.0.1
  TBC-WEAKAURA, by Ryecoke, Jun 10 2021 [2.5.1 TBC], **9 stars /
  10237 views / 159 installs**, 4 comments, "No custom code". Strongest
  TBC-native feral suite by installs. Caveat (page-carried): "created for the
  original TBC Classic and may not work as expected in the TBC Classic
  Anniversary."
- Description (CONFIRMED): Cat Form = Energy Bar, Combo Point Tracker,
  **Powershifting Bar**, Energy Tick Bar, Mana Bar; Bear = Rage Bar, Swing
  Timer, Mana Bar; Cooldown Tracking incl. Tiger's Fury; Buff Tracking incl.
  Omen of Clarity / Clearcasting; Debuff Tracking incl. Faerie Fire, Mangle,
  Rip, Rake; Queued Attacks: Maul.
- Screenshot (VIEWED `60ae70c946e73140392d66a3.png`, 273×199, CONFIRMED):
  top row of 4 buff icons with big duration/count numbers (4, 13, 4, 3, green
  `+279`); blue mana bar with `4833` readout; 12-icon ability/cooldown grid;
  bottom row of small icons. Full-suite grid (all specs), feral elements are
  the buff durations + mana bar + cooldown grid rows.
- Observed layout: per-form resource bars (energy/CP/tick/powershift for cat)
  + full cooldown/buff/debuff icon grid + Maul queue tracking.
- Our-model mapping: energy/CP/tick/powershift bars ≈ our bars + `druid_energy`
  tick domain (display precedent for the TTD/pooling tick bar); TF/Omen/FF/
  Mangle/Rip/Rake icons ≈ **D-T2** slot set {mangle, rip, rake, shred, tf} +
  Omen glow (already shipped `classes/druid.lua:950-964`); Maul queue ≈ our
  Maul-grey slot (same signal, icon-row form). Powershifting bar is the
  in-scope precedent for shift-count/mana-cost reads — our guide deliberately
  REMOVEs powershift (no honest Furor/Wolfshead probe), so borrow the DISPLAY
  language only, never the shift rule.
- Fit notes: TBC visual-check target #1 for bars + D-T2; powershift-bar copy
  must not imply a shift recommendation.

### D3. Feral/Druid UI by Meatslab (SoD) — https://wago.io/jHooVKdGs
- Header (waited scrape, CONFIRMED): `Feral/Druid UI by Meatslab - Season of
  Discovery`, v1.0.36 CLASSIC-WEAKAURA, by Meatslab#2729, Feb 15 2024
  [1.15.1 SoD], **11 stars / 9250 views / 142 installs**, 42 comments,
  37 versions, "No custom code".
- Description (CONFIRMED): "Supports all new SoD rune tracking. Includes
  Caster, Cat form, and Bear form bars for Phase 2 of Season of Discovery
  druids." Linked sub-auras: Energy Tick (`7DlodicT4`), Powershift counter
  (`tEf7cR1dG`), Weapon CD tracker (`06P6BwyKw`). Notable trigger caveat
  (page-carried): cat auras key on Form 3 (requires Aquatic Form known) —
  client-data gating detail, not our model.
- Screenshot (VIEWED `65c915b3cd003b1cb7b1698f.png`, 390×171, first of 6,
  CONFIRMED): 5 empty tracker slots over a gold `100` bar; green `911` +
  teal `979` resource bars; 5-icon cat ability row; bottom utility row with
  count badges (9, 8, 12). Full feral dashboard: bars + cat icon row + rune/
  utility row.
- Observed layout: per-form bars + 5-icon cat row + utility/rune row with count
  badges.
- Our-model mapping: cat icon row ≈ **D-T1 Bleed Core** {mangle, rip, rake,
  shred} + bite/shred builder reads; energy-tick sub-aura ≈ our tick-bar
  domain; powershift counter ≈ display precedent (same no-rule caveat as D2);
  weapon-CD tracker ≈ trinket/CD slot story (our trinket1/2 row).
- Fit notes: SoD visual-check target #2 (rune-era kit); cat-row density (5
  icons) validates D-T1's 4-icon minimalism — one row, no scroll.

### D4. Luxthos - Druid (Classic Era) — https://wago.io/JXjF4Itec
- Header (waited scrape, CONFIRMED): `Luxthos - Druid (Classic Era)`,
  v1.15.5-6 CLASSIC-WEAKAURA, by Luxthos, Jan 23 2025 [1.15.5 SoD client],
  **4 stars / 12104 views / 55 installs**, 6 versions. Major-author Era line.
- Description (CONFIRMED): "Fully customizable Druid WeakAuras for World of
  Warcraft: Classic Era. They contain a complete setup for all Druid
  Specializations by covering rotational abilities, cooldowns, resources and
  utilities." v1.15.5-6 note: "Added Omen of Clarity." Customization =
  reorder/change-count without code (same no-code UX bar as the shaman
  Luxthos line in `bench/weakaura_templates_2026-10-19.md` §A1).
- Screenshot: GIF downloaded (609×355, 6.2 MB) but NOT viewed — layout from
  description text only (stated, UNCONFIRMED at pixel level).
- Observed layout (text-level): rotational-ability icons + cooldowns +
  resources + utilities, all-specs, Omen of Clarity covered.
- Our-model mapping: rotational row ≈ **D-T2**; Omen coverage ≈ our Omen glow;
  no-code reorder ≈ our `hud_template` select UX bar (one-click curated look).
- Fit notes: Era visual-check target from a major author; in-client
  side-by-side owed before gallery copy cites any pixel geometry.

### D5. Cat Rotation (TBC priority icons + powershift helper) — https://wago.io/HRaLYFROP
- Header (waited scrape, CONFIRMED): `Cat Rotation`, v1.0.5 TBC-WEAKAURA, by
  Stu, May 4 2026 [2.5.5 TBC (Test)], 1 star / 1205 views / 1 install,
  6 versions, "No custom code". No screenshots on the page (stated).
- Description (CONFIRMED, the card — full trigger spec on-page): priority
  icon set for Cat Form driven by energy/CP/target-health/debuffs/threat/
  energy-ticks: FB at ≥35 energy + ≥4CP + target ≤1200 HP; Rip at ≥30 energy
  + ≥4CP + missing Rip + target >1200 HP + Mangle present; Mangle at ≥40 to
  maintain or as CP builder without Shred position; Shred at ≥42 + <4CP +
  Mangle present + no aggro; Powershift icon with mana gate (≥580) + per-move
  tick-timing branches (22–42 energy Shred window, 20–40 Mangle window,
  10–30 Rip window, 15–35 FB window, each with tick->1s vs energy-starved
  legs).
- Observed layout (text-level): single priority icon shown at a time
  (conditional-icon pattern) + powershift-next-move helper. No row geometry
  observable (no screenshots) — UNCONFIRMED at pixel level.
- Our-model mapping: FB/Rip/Mangle/Shred conditions ≈ our guide-rule inputs
  (energy bands, CP≥4, Mangle/Rip presence, TBC costs Mangle-40/Shred-42 per
  `druid_guide.lua:317-318`); tick-timing legs (tick>1s) ≈ our tick-window
  math (`druid_energy` 19–22 window); conditional-single-icon ≈ our
  next-action-guide frame domain (NOT the HUD row — do not conflate).
- Fit notes: closest TBC cat-priority spec found; cross-check our TBC guide
  rules (T1–T5) against its energy/CP/debuff gates. Powershift legs are
  display-logic only on our side (no shift rule without probe).

### D6. Luxthos Druid - TBC Anniversary (Igosha restoration) — https://wago.io/iKqXOq7EM
- Header (waited scrape, CONFIRMED): `Luxthos Druid - TBC Anniversary`,
  v1.0.0-2 TBC-WEAKAURA, by Igosha, Aug 10 2026 [2.5.6 TBC (Test)], 1 star /
  725 views / 2 installs, "No custom code". Restoration of the Luxthos TBC
  druid pack (original author's own pack per page).
- Description structure (CONFIRMED): one import (root + Core/Dynamic/Utilities
  anchored on Core); **Core = the original form-driven icon row
  (caster/cat/bear share six x-slots via form-buff triggers) + resource bars,
  combo points, cast bar**; 145-entry ability/talent coverage audit; Anniversary
  fixes (Spell-Known talent-dedup, load-gate sanitation, lowest-rank gates,
  API renames); added Player Health Bar + maintenance reminders (MotW/Gift,
  Thorns, **Omen of Clarity** with Show-if-Applied/Missing/Always behavior,
  hidden in rested areas).
- Observed layout (text-level): single shared 6-slot icon row that swaps by
  form + resource/CP/cast bars + health bar; Omen as maintenance reminder.
- Our-model mapping: 6-slot form-driven row ≈ our fixed-order HUD row
  (different mechanism — ours is per-class static order per `hud.lua:467-471`,
  not form-swapped; cite as layout-density precedent, not mechanism);
  resource/CP bars ≈ bars domain; Omen reminder ≈ our Omen glow (ours is
  proc-glow, theirs is upkeep reminder — complementary, not identical).
- Fit notes: TBC Anniversary-client-correct (2.5.6 stamp, Spell-Known gates
  per the TBC name-vs-id rule) — best client-hygiene reference for TBC
  gallery copy. Pixel layout UNCONFIRMED (no screenshots viewed).

### D7. Feral Buff, Debuff, Power Bar (Classic+SOD) — https://wago.io/WVjV2Fes6
- Header (waited scrape, CONFIRMED): `Feral Buff, Debuff, Power Bar
  (Classic+SOD)`, v1.0.2 CLASSIC-WEAKAURA, by Grillitassu, Dec 29 2025
  [1.15.8 SoD], 0 stars / 2476 views / 0 installs, 3 versions. Page body is
  editor JSON (no prose description) — layout UNCONFIRMED beyond the title.
- Observed layout: buff/debuff/power-bar grouping per the title only.
- Our-model mapping: buff/debuff ≈ **D-T2** upkeep reads (rip/rake/mangle +
  TF/Omen); power bar ≈ bars domain.
- Fit notes: minor card — title-evidence only; counts toward the "buff+debuff+
  power in one pack" consolidation precedent (same one-stop-shop direction as
  our HUD+guide+practice), no geometry to borrow.

## 2. Shortlist for the template gallery (validation owner: orchestrator)

1. **D-T2 "Full Feral + Pops" vs Sabimaru SoD suite (D1) — visual-check
   target #1.** Highest-install SoD/Era feral suite (358 installs); icon row +
   bars + stack counters mirror our Core-vs-bars split. In-client
   side-by-side before gallery copy.
2. **TBC bars + D-T2 vs Ryecoke (D2) — visual-check target #2.** Only TBC
   suite with energy/CP/tick/powershift bars + Omen + Maul-queue signal;
   validates our tick-bar display and Maul-grey languages.
3. **D-T1 "Bleed Core" density vs Meatslab cat row (D3).** 5-icon SoD cat row
   confirms a 4-icon core row reads clean — keep D-T1 minimal, no new slots.
4. **Core rows vs Luxthos Era line (D4) — UX bar.** No-code reorder is the
   standard our `hud_template` select must meet.
5. **TBC guide cross-check vs Cat Rotation triggers (D5).** Energy/CP/debuff/
   tick gates to reconcile against our T1–T5 rules (filed as rotation
   follow-up, not a template change).
6. **TBC Anniversary hygiene vs Igosha restoration (D6).** Spell-Known gates +
   2.5.6 stamp = the client-correctness reference for any TBC gallery claims.
7. **D-T3 "Bear Guard" — NO external feral-bear layout found this round.**
   Bear-tank feral HUD remains UNCONFIRMED in-client (same gap as
   hud_templates §D-T3). Do not ship bear-gallery copy beyond the current
   "unaﬀordable-grey" tell without a bear-tank source.

## 3. Per-attempt evidence log (URL + what showed; failures UNCONFIRMED)

| URL | Catalog + recipe | What showed |
|---|---|---|
| `https://wago.io/HRaLYFROP` | firecrawl_scrape wait 8000 (1 credit) | CONFIRMED: v1.0.5 TBC-WEAKAURA, Stu, 1★/1205 views/1 install, full FB/Rip/Mangle/Shred/powershift trigger spec (§D5) |
| `https://wago.io/36c1KstPG` | firecrawl_scrape wait 8000 | CONFIRMED: v1.0.1 TBC-WEAKAURA, Ryecoke, 9★/10237/159, per-form bars + Omen + Maul queue (§D2) |
| `https://wago.io/JXjF4Itec` | firecrawl_scrape wait 8000 | CONFIRMED: v1.15.5-6 CLASSIC-WEAKAURA, Luxthos, 4★/12104/55, Omen added (§D4) |
| `https://wago.io/bQynAWaKe` | firecrawl_scrape wait 8000 | CONFIRMED: v1.5.8-45 CLASSIC-WEAKAURA, Sabimaru, 38★/25116/358, suite feature list (§D1) |
| `https://wago.io/jHooVKdGs` | firecrawl_scrape wait 8000 | CONFIRMED: v1.0.36 CLASSIC-WEAKAURA, Meatslab, 11★/9250/142, SoD rune bars + sub-aura links (§D3) |
| `https://wago.io/MPGarWX9h` | firecrawl_scrape wait 8000 | CONFIRMED CATA-WEAKAURA (Bisonpasfuté, Cataclysm 4.4.2) — DROPPED per scope (§4) |
| `https://wago.io/iKqXOq7EM` | firecrawl_scrape wait 8000 | CONFIRMED: v1.0.0-2 TBC-WEAKAURA, Igosha, 1★/725/2, Core/Dynamic/Utilities + 6-slot form row (§D6) |
| `https://wago.io/classic-weakauras/classes/druid/feral` | firecrawl_scrape wait 8000 | CONFIRMED: 2,187 feral results; top hits Grillitassu Classic+SOD + Voqx FF Tracker (discovery only) |
| `https://wago.io/WVjV2Fes6` | firecrawl_scrape wait 8000 | CONFIRMED header (v1.0.2 CLASSIC-WEAKAURA, Grillitassu, 1.15.8 SoD); body = editor JSON, no prose (§D7) |
| `https://wago.io/0xJX9MUYx` | firecrawl_scrape no-wait then wait 8000 | Shell both times (LEN 395 → 2414 shell, no content) — page removed/private, UNCONFIRMED; only the websearch snippet survives (T's Classic CP UI: hide-out-of-Cat, per-point indicators, 5-CP glowbar) |
| `https://wago.io/azeOt4bKZ` | firecrawl_scrape wait 8000 (earlier batch) | Shell (LEN 2414, no content) — UNCONFIRMED at page level; only the websearch snippet survives (Rockleaf SoD: feral bleeds/buffs, all-form mana+resource bar, powershift icon with shifts-left + mana cost) |
| SearXNG 3 queries | searxng_web_search | DEGRADED (429/CAPTCHA across engines) — recorded, did not serve |
| `firecrawl_search` 1 query | firecrawl_search | Invalid request body (known quirk) — recorded, did not serve |
| `firecrawl_agent` 1 job | firecrawl_agent (prompt + maxCredits) | REJECTED `f72cd27a…` — recorded, fell back to scrape-per-URL |
| `firecrawl_map` wago classic feral | firecrawl_map (url + search + limit) | Served but content-free (`links: []`) — discovery via websearch instead |
| Screenshots (3 PNGs) | curl → /tmp/opencode/druidstyles/ + view | VIEWED: Sabimaru 375×159, Meatslab 390×171, Ryecoke 273×199 (§D1–D3). Luxthos GIF downloaded, NOT viewed |

## 4. Uncertainty ledger + do-not-retry list

- Pixel geometry (icon size/spacing/orientation) for ALL cards is UNCONFIRMED —
  screenshots show composition, not knob values. No geometry invented.
- Wrath/Cata/retail drops this round: `MPGarWX9h` CATA-WEAKAURA (Bisonpasfuté
  snapshotting pack — would otherwise be the DPE/snapshot reference; excluded
  by scope, NOT carded); Warperia-style WotLK druid packs and Afenar/Luxthos
  retail lines sighted in search but out of scope, not pursued.
- Do NOT re-try: no-wait wago.io scrapes (shell, re-confirmed); `0xJX9MUYx`
  + `azeOt4bKZ` (shell even WITH wait — removed or bot-walled, snippet-only);
  SearXNG druid queries without backoff (rate-limited); `firecrawl_search`
  with anything but a minimal body (invalid-body quirk); `firecrawl_agent`
  with maxCredits-style extras (rejected — keep bodies URL + tiny prompt).
- Class-Discord pins and guide-UIs: NOT surveyed this round (wago.io suite
  depth consumed the lane). Filed as follow-up, not blocked — D1–D6 cover the
  template-gallery inputs (energy/CP, Rip/Rake, TF/pops, powershift helpers).
- Nothing copied: no import strings, no code, no assets. Links only.
- Next productive step: in-client side-by-side (TESTING.md session), not more
  scraping.
- Validation owner: orchestrator. Method to re-verify: re-scrape the §3 URLs
  with the wait-recipe, re-check each our-side line ref
  (`classes/druid.lua:1972-1984`, `hud.lua:125-129`,
  `bench/hud_templates_2026-10-19.md` §4), confirm this file is still the only
  `bench/druid_styles_*` file.
