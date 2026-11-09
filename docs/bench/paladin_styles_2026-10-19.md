# bench/paladin_styles_2026-10-19 — top ret-paladin HUD/WeakAura styles (TBC + Era/SoD ONLY)

Desk: paladin-styles (subagent, READ-ONLY except this NEW file). Date: 2026-10-19.
Scope: TBC Classic (2.4.3/2.5.x incl. Anniversary) + Classic Era/SoD (1.15.x) ret-paladin
HUDs: seal-twist trackers, CS/Judge cooldown HUDs, SoD rune trackers. NO Wrath (3.x),
NO Retail — Wrath/Retail sightings dropped (§5 ledger). One SoD-era CurseForge ADDON
carded as direct-competitor reference (not a WA, flagged as such).
No addon/test/bench file touched; no git; no code or import strings copied (describe + link only).

Target file verified absent in-lane via glob (`bench/paladin_styles_2026-10-19.md` → no files found)
before writing.

## 0. Our-model reference (read-only, CONFIRMED on disk 2026-10-19)

- `classes/paladin.lua:3385-3398` — `ST.PALADIN.HUD_SLOTS` (12 keys): `cs` (35395),
  `judgement` (20271), `consecration` (26573), `exorcism` (879), `trinket1` (inv 13),
  `trinket2` (inv 14), `wings` (31884), `soc` (20375), `sob` (guide_sob_spell_id),
  `how` (guide_how_spell_id), `holy_shock` (20930), `aura_mastery` (407624).
  NOTE: `bench/hud_templates_2026-10-19.md` §1 describes the older 7-slot set
  (pre soc/sob/how/holy_shock/aura_mastery); mappings below use key names, valid either way.
- `hud.lua:125-129` — LAYOUT_KEYS: `hud_x/y/scale/icon_size/match_bar_width/spacing/
  orientation/border_size/border_color/font/text_size/text_outline/locked`.
- Template shorthand: **P-T1 "Twist Core"** {cs, judgement, exorcism, wings},
  **P-T2 "Full Ret + Trinkets"** (all base-7 + match-width), **P-T3 "Minimal"** {cs, judgement}.
  SoD-native slots (soc/sob/how/holy_shock/aura_mastery) extend P-T2, not P-T1.

## 1. Method + tooling record (per standing firecrawl discipline: small bodies, record what served)

- Catalogs enumerated first in-lane: firecrawl (28 tools via tool search) + searxng
  (4 tools: instance_info, suggestions, web_search, web_url_read).
- Served this round: **`default.websearch`** (discovery, 4 queries, all returned),
  **`firecrawl_scrape` with `waitFor: 8000` (+ `maxAge: 0` on retry)** per the
  weakaura_templates wait-recipe (7 page scrapes, MDLEN 2.4k–13.6k), **`default.webfetch`**
  (1 CurseForge page, full description), shell `curl` (5 screenshot PNGs, all VIEWED),
  `default.read` (3 screenshots viewed).
- FAILED this round (recorded, fell back per discipline):
  - `firecrawl_agent` ×2 — first rejected `effort` key ("Unrecognized key in body"),
    retry without it errored (Error ID 8e7ff4c80f48496899ffe3f7008e5062). Operator
    correction (small schema-shaped bodies) honored — no further agent attempts.
  - `firecrawl_search` ×1 — "Invalid request body" (matches lessons.md: broken on this
    deployment). No retry; websearch carried discovery instead.
  - `searxng_web_search` ×2 — rate-limited (brave/duckduckgo/google/startpage all
    suspended/CAPTCHA mid-round; matches the weakaura_templates §0 note). Instance
    capabilities verified reachable; engines simply throttled. No retry; websearch carried.
- Layout evidence bar: CONFIRMED = scraped page text cited the layout, or screenshot
  VIEWED in-lane (stated per card). Listing-snippet-only layouts marked as such.
  UNCONFIRMED in caps otherwise.

## 2. Style cards (ranked by gallery value)

### S1. Surveillant Seal Twist Swing Timer — SoD twist reference (RANK 1)
- URL: https://wago.io/0i19EUqcz — `v1.0.8 CLASSIC-WEAKAURA` [1.15.6 SoD], by Surv,
  13 stars, 26367 views, 73 installs, 9 versions, "No custom code" (scraped CONFIRMED).
- Companion variants (sighted as link text, bodies UNCONFIRMED): dual-seal
  Seal-Stacking/Exodin version https://wago.io/NQ_O1D5ky, any-class swing-only
  https://wago.io/0SCWuXniu.
- Observed layout (screenshot VIEWED `67ae4cb1056f33dc6cebf453.png` + description scraped):
  single horizontal swing bar, blue fill progress with white leading edge, RED tick
  (end of filler / start of danger), BLACK danger stretch, TWO green ticks (twist-window
  start + late-twist for Double Judge/Pro Judge), seal icon at bar right with duration
  number. Annotated labels: "Filler Window / Danger Zone / Twist Window / Late Twist
  (for Pro & Double Judging)". Bar colors: Blue = filler, Red = danger (don't cast),
  Green = twist window (last 0.4 s) or swing-ready. Attack-speed tracker turns red below
  the 3.0 haste cap (cue: wait for GCD before twisting). Seal indicators show both seals
  while dual-active. Sound cues + peripheral color shifts reduce bar-staring. Parry-haste
  and stored/immediate extra attacks handled; stuck-full bar = auto-attack-off diagnostic.
  Latency calibration guidance on-page (shift ticks/cues by latency−50 ms). Author also
  wrote the Wowhead SoD paladin rotation guide + "Double Judge Twisting" / "Complete Guide
  to Seal Twisting" videos (linked on-page).
- Our-model mapping: the twist-band + tick vocabulary maps 1:1 onto our bars domain
  (twist window band, danger-zone analog to the rogue pool band, haste-cap read).
  Nothing maps to HUD_SLOTS (bar, not icon row) — correct separation. Latency-shift
  guidance ≈ our `lag_multiplier`/`lag_offset` calibration (twist.lua) — gallery copy
  should name the equivalence.
- Fit notes: gallery ANCHOR for SoD twist. Borrow list: (1) danger-zone red stretch
  language, (2) late-twist second tick for Double Judge, (3) haste-cap red read,
  (4) stuck-full/auto-attack-off diagnostic. Have list: 0.4 s window math, twist band,
  success text. In-client side-by-side owed (TESTING.md session).

### S2. Faelor Paladin Suite (TBC) — most-installed TBC suite (RANK 2)
- URL (Core): https://wago.io/EwsoAhIRl — TBC-WEAKAURA, by Faelor#1811, May 2021 [2.5.1],
  80 stars, 28270 views, 3424 installs, 9 versions, 8 screenshots (scraped CONFIRMED).
- Suite = 5 separate WAs (CONFIRMED from description): Core (EwsoAhIRl) + Dynamic
  (SYldNDH4M) + Auras (LDdC3ozEr) + Non-Core (yWDJrdFsY) + Maintenance (R4LVSxNwW);
  pieces 2–5 anchor to Core position; split for safe partial updates.
- Observed layout (2 screenshots VIEWED + description scraped): TWO-ROW icon grid —
  top row ~8 spec/rotation icons with a thin blue resource (mana) bar above showing
  "100%", bottom row ~8 smaller aura/blessing/seal icons; separate judgement tracker
  ("Judgements from other paladins" with arrows + 44 s durations) and seal-stack
  readouts. Conditional loading: icons appear only when the ability is learned/talented.
  TWO melee swing trackers (thin default without numbers; thicker numeric variant
  "3.2 / 1.8 / 0.3 sec"); GCD spinner on icons; red inactive-seal icons; MP5 spark.
  Author EXPLICITLY defers advanced seal-twisting to specialized WAs ("Better Melee
  Swing Timer … suggested you get a WeakAura or addon that specializes in that") and
  plans a haste-aware (Bloodlust/Heroism/haste-potion) twist swing timer.
- Our-model mapping: two-row icon grid + mana bar ≈ P-T2 Full expanded across two rows
  (our contract is single-row — gallery copy must note the row-count difference, not
  smuggle a second row); conditional loading ≈ our provider-hide + `hud_show_*` toggles;
  GCD spinner ≈ our cooldown swipes; mana bar ≈ `hud_mana_tint` key (gallery should name it).
- Fit notes: visual-check target for P-T2 density on TBC. Borrow: judgement-attribution
  row concept (which paladin's JotC is up — matches our JotC mini-bar problem space);
  have: single consolidated row, provider-hide. Five-piece split is packaging, not layout.

### S3. Gaffaen's Seal Twist Bar V2 (TBC) — guide-recommended twist bar (RANK 3)
- URL: https://wago.io/6eI19e70L — `v1.0.2 TBC-WEAKAURA` [2.5.1], by Gaffaen,
  10 stars, 10432 views, 204 installs, 5 screenshots, "No custom code" (scraped CONFIRMED).
  V2.0.3 successor https://wago.io/rpP7Xejei (dynamic GCD lines from Drums/spellhaste;
  sighted via search snippet, body UNCONFIRMED). Recommended in the TBC twist video guide
  https://www.youtube.com/watch?v=PIjJ2pcnLVQ ("swing timer broken into GCD sections,
  last white bar = twist window, red line = last moment for another spell").
- Observed layout (description scraped; screenshots NOT viewed — layout from text):
  swing timer with GCD lines + twist-window line; seal color codes — Green = SoC active,
  Red = do-not-use-GCD, Orange = SoB active, White = other/no seal; active-seal indicator;
  dynamic GCD lines for Drums of Battle + Heroism/Bloodlust; SoR added as valid twist seal.
- Our-model mapping: GCD-sectioned bar + seal-color language ≈ our bars domain (twist
  band + GCD awareness); color-per-active-seal ≈ our seal-state reads. No HUD_SLOTS mapping.
- Fit notes: second twist-bar dialect vs S1 (color-code vs tick-mark school). Borrow:
  dynamic Drums/Hero GCD-line shift (haste-source-aware geometry — our lag calibration
  covers latency, not haste-source shifts); active-seal color code. 204 installs + video
  recommendation = proven TBC demand.

### S4. TBC RetPal SealTwist Rotations (CurseForge ADDON, not a WA) — direct competitor (RANK 4)
- URL: https://www.curseforge.com/wow/addons/tbc-retpal-sealtwist-rotations — by
  Cokenosugar-Nightslayer (fetched via webfetch, full description CONFIRMED).
- Observed feature set (page text): seal-twisting QUEUE ICONS (rotation queue, not just
  timer); "Swedge-style swing bar" under the queue icons (names our shape explicitly);
  Command/Blood/Martyr timing markers; seal-aware idle state (pre-pull first-seal prep);
  PERFECT streak counter for successful twists; auto-adapts to weapon speed + haste
  (lust/potion); in-game settings panel (world/home latency, Blood/Martyr lead timing,
  deadzone, safety buffer, CS delay allowance, spell-queue/update-interval, bar display,
  icon size/scale/opacity/spacing/position, debug text); slash commands
  /retseal /sealrot /strsq /stq; embedded LibClassicSwingTimerAPI; Horde/Alliance macro sets.
- Our-model mapping: queue icons ≈ our next-action guide frame (guide domain, CONFIRMED
  adjacent); swing bar + markers ≈ our bars + twist band; latency/deadzone/safety-buffer
  panel ≈ our twist lag calibration keys; PERFECT streak ≈ our practice score modules.
  Single-source feature list reads like our P1 bank (GCD-aware reseal marker, competitor_gaps
  §P1) shipped by someone else — verify overlap before claiming gaps.
- Fit notes: closest thing to OUR addon found anywhere (queue + bar + latency panel in one
  package). Gallery value is competitive-positioning, not borrowing: our differentiators
  are per-class unification (6 classes, one addon), SoD-variant coverage, and practice
  drills. Do NOT copy queue-icon geometry or streak scoring verbatim.

### S5. Kaedin's Seal Twist Indicator & Paladin UI TBC 2026 — Anniversary-current (RANK 5)
- URL: https://wago.io/g07nbuxuJ — `v1.0.0 TBC-WEAKAURA` [2.5.5 TBC (Test)], by romqqvk,
  Apr 2026, 0 stars, 755 views, 0 installs, "No custom code" (scraped CONFIRMED).
  Fork of https://wago.io/Fj5FjlAEq (same title; parent body UNCONFIRMED, presumed same).
- Observed layout (description scraped; no screenshots on page): swing timer with
  per-seal tick placements (SoB/SoR/SoC); while SoC active the attached seal icon FLASHES
  during the last 0.4 s; "Ding" on successful twist (deletable via one Condition);
  current-seal display; JUDGEMENT ATTRIBUTION — which seal each paladin applied to
  target AND focus; Reckoning duration tracker with 75/50/25% colored ticks, bars
  re-color per spent stack (4 stacks).
- Our-model mapping: 0.4 s flash + ding ≈ our twist success text/score path (bars +
  practice domains); judgement-attribution ≈ our JotC mini-bar problem space (same as
  S2's tracker — two independent implementations confirm demand); Reckoning ticks ≈
  segmented-bar language (no HUD slot; bars-domain borrow candidate).
- Fit notes: ONLY Anniversary-client-dated (2.5.5 Test) twist WA found — TBC template
  verification target despite 0 installs (new). Borrow: per-seal tick placements
  (SoB vs SoC vs SoR geometry, not one generic window); judgement-on-focus.

### S6. Baranor's Seal Twist Swing Timer line — twist-mark convention origin (RANK 6)
- URLs: fork https://wago.io/L4ZVJ8OAu (v1.0.0, 0 stars, 1651 views, 4 installs) of
  original https://wago.io/MFeEVBM79 (v1.5.0-9, sighted via search, body UNCONFIRMED).
  Both TBC-WEAKAURA [2.5.1] (scraped CONFIRMED for the fork).
- Observed layout (fork description scraped; no screenshots sighted): GREEN mark on the
  swing timer = twist point (change seals on/after green); optional RED line = last
  possible SoC moment before GCD makes the twist impossible (default 1.5 s pre-swing,
  moves with spell haste).
- Our-model mapping: green-mark/red-line ≈ our twist band + reseal-marker P1
  (competitor_gaps §P1: "marker computed from GCD + twist window, distinct from our
  twist band") — Baranor's red line IS the shipped precedent for P1's ask.
- Fit notes: convention origin (green = go) referenced by later authors ("mine or
  Baranor's", Surveillant video). Cite in gallery copy for the twist band; P1 stays
  the build item (our marker must be GCD-aware per sim, not a fixed 1.5 s).

### S7. Soltharion TBC Seal Twist Proc Tracker — proc/success-text pattern (RANK 7)
- URL: https://wago.io/Gwsxs5Qel — `v1.0.1 TBC-WEAKAURA` [2.5.1], by Soltharion,
  4 stars, 5536 views, 47 installs, 2 versions (scraped CONFIRMED).
- Observed layout (screenshot VIEWED + description scraped): dual-seal tracker
  (max-rank SoB + rank-1 SoC, name-based triggers — "IDs not picked up in combat logs");
  success feedback = glowing seal icon + "Seal Twist Success" text popup. SoC ranks
  20424/20944/20945/20946/20947 enumerated on-page (matches our twist.lua:22-29 + 29385).
- Our-model mapping: dual-seal display ≈ our seal-state reads (no HUD slot — state,
  not cooldown); success text ≈ our twist success text path (bars `on_bar_update`
  hook); name-based triggers CONFIRM our TBC name-resolution discipline (lessons.md).
- Fit notes: smallest card, kept for the success-feedback pattern + independent
  confirmation of our SoC proc-id set. Anniversary-compat UNCONFIRMED (page carries the
  standard "may not work as expected" notice).

### S8. Sealor Paladin Auras SoD P8 — rune-adaptive full pack (RANK 8)
- URL: https://wago.io/I54CPyQrg — `v1.0.3 CLASSIC-WEAKAURA` [1.15.4 SoD], by
  Cows_n_Muffins, 0 stars, 1259 views, 2 installs, 1 screenshot (scraped CONFIRMED).
  Fork of "Beez Paladin Auras" https://wago.io/y3EZtdRm9 (body UNCONFIRMED).
- Observed layout (screenshot VIEWED): FULL UI PACK — top-center warnings
  ("✦ AURA MISSING ✦" / "✗ BLESSING MISSING ✗"), two-row ability grid flanking unit
  frames (combat abilities left, utility right), red "NO SEAL ACTIVE" banner,
  blue mana bar (2342/2342 with status text), DUAL Main-Hand swing bars (blue + red,
  1.3 s readout). Description: dynamic ability bars resize by selected runes (P2/P3
  runes added); CDs change with active runes; visual warnings for Horn of Lordaeron /
  Inspiration Exemplar selected-but-inactive; swing timer with GCD tick + twist timing;
  DPS icons centralized (Divine Shield/Avenging Wrath swapped).
- Our-model mapping: two-row combat/utility split ≈ P-T2 stretched across rows
  (same row-count caveat as S2); rune-adaptive bars ≈ our SoD-variant mechanism
  (ERA+known-spell gating — standing rule, never client-version); missing-aura banner
  ≈ upkeep-tell domain (guide frame, not HUD); dual swing bars with readouts ≈ our
  bars domain; mana bar ≈ `hud_mana_tint`.
- Fit notes: only SoD P8-dated full pack found (Oct 2024; P8 content needs the
  sod-paladin-variants input list — Holy Power stacks etc. — before any gallery copy
  claims parity). Layout reference for SoD, not a slot donor.

### S9. Luxthos Paladin lines — Era + TBC suite baseline (RANK 9)
- Era: https://wago.io/bAgMk3Ty_ — `v1.15.3-4 CLASSIC-WEAKAURA` [1.15.5 SoD], by Luxthos,
  6 stars, 13394 views, 50 installs (scraped CONFIRMED). TBC Core:
  https://wago.io/ZjQTDI8SL — `v1.0.0 TBC-WEAKAURA` [2.5.1], 1 star, 3211 views,
  12 installs (scraped CONFIRMED). Companion pieces (Utilities Hv4l1m9Je, Dynamic
  1pWLlzb1H — sighted link text, bodies UNCONFIRMED). Layouts: listing-level only,
  group structure UNCONFIRMED (no screenshots retrieved this round; prior lane confirmed
  luxthos.com preview PNGs are promo banners, not UI — do NOT re-try).
- Observed (listing text CONFIRMED): "entirely customizable without any code or
  WeakAuras knowledge … change design, borders, amount of icons, order of abilities
  to match keybinds"; full setup per spec (rotational abilities, cooldowns, resources,
  utilities); Core/Dynamic/Utilities split; group scale + drag positioning; cooldown
  numbers via client option.
- Our-model mapping: per-spec icon rows ≈ P-T1/P-T2 shape (single-row assumption
  UNCONFIRMED); no-code customization + keybind-order = the UX bar our `hud_template`
  select must meet (already the stated promise in hud_templates §7).
- Fit notes: baseline, not borrow — biggest author brand in the corpus, weakest
  per-page layout evidence. Keep as the "no-code customization" citation in gallery copy.

### S10. SOD Ret Pally Rotation Tracker (Malamo) — minimal SoD row (RANK 10)
- URL: https://wago.io/eZZQtKlUF — `v1.0.2 CLASSIC-WEAKAURA` [1.15.1 SoD], by Malamo,
  0 stars, 1244 views, 0 installs, no screenshots (scraped CONFIRMED).
- Observed (description only): "Tracks Ret Pally rotation cooldowns for Crusader Strike,
  Divine Storm, Seal of Command, Judgement, and Exorcism"; v1.0.2 note "icons no longer
  fade when showing cooldowns" (icon-persistent cooldown display).
- Our-model mapping: CS/DS/SoC/Judge/Exo set ≈ P-T1 {cs, judgement, exorcism, wings}
  + soc slot + DS-shape (Wrath-kit DS on SoD maps to our sob-slot DS convention per
  classes/paladin.lua:3376-3378); icon-persistent CDs ≈ our swipe-over-icon rendering
  (vs fade/hide alternatives).
- Fit notes: niche (0 installs) but the ONLY pure SoD CS/DS rotation row found — kept
  as the minimal-row precedent for a SoD P-T1 extension. No layout to borrow (no shots).

## 3. Shortlist for the template gallery (validation owner: orchestrator)

1. **SoD twist anchor: S1 (Surveillant).** Deepest twist model in scope (filler/danger/
   twist/late-twist, haste-cap read, Double-Judge tick, latency-shift recipe, Exodin
   dual-seal variant). Borrow the band language; verify in-client.
2. **TBC suite anchor: S2 (Faelor).** Most-installed TBC paladin suite (3424 installs);
   two-row grid + mana bar + judgement-attribution = P-T2 density check target.
3. **TBC twist-bar second dialect: S3 (Gaffaen).** Video-recommended; seal color codes +
   dynamic Drums/Hero GCD lines. Compare against S1 before standardizing band copy.
4. **Competitor to beat: S4 (RetPal SealTwist Rotations addon).** Queue icons + streak +
   latency panel in one package; our answer is per-class unification + SoD variants +
   practice drills. Verify P1-overlap before claiming the gap.
5. **Anniversary verification target: S5 (Kaedin's).** Only 2.5.5-dated twist WA;
   per-seal ticks + focus-judgement attribution are the two borrows.
6. **Convention citation: S6 (Baranor line).** Green-mark origin; red-line = shipped
   precedent for our P1 reseal-marker ask.
7. **SoD pack reference: S8 (Sealor).** Rune-adaptive bars + full-pack layout; SoD
   gallery copy waits on the Holy-Power-input shopping list (sod_paladin_variants §7).
8. **UX bar citation: S9 (Luxthos).** No-code customization promise our template select
   must meet; no layout borrows claimed.
9. **Minimal-row precedent: S10 (Malamo SoD tracker).** CS/DS/SoC/Judge/Exo persistent-icon
   row grounds a SoD P-T1 extension.
10. **Pattern citation: S7 (Soltharion).** Success-text feedback + name-trigger discipline.

## 4. Guide-UI / community sources (secondaryask coverage)

- Surveillant's Wowhead SoD paladin rotation guide + "Double Judge Twisting" and
  "Complete Guide to Seal Twisting" videos (linked from S1 page; existence CONFIRMED as link text, contents NOT reviewed — guide-UI deep read stays open).
- TBC twist video guide https://www.youtube.com/watch?v=PIjJ2pcnLVQ (Gaffaen
  recommendation + GCD-section bar language; transcript snippets via search CONFIRMED).
- Surveillant "Rotation Twister" WA (swing-speed→rotation advisor with Training-Wheels
  text mode, Drums/haste-dynamic; sighted via video description
  https://www.youtube.com/watch?v=XKoyUGf9VFI — page NOT scraped, card UNCONFIRMED,
  flagged for a follow-up lane, not this file).
- "The Light Club" Discord cited as TBC paladin help venue (r/classicwowtbc comment;
  pin contents UNCONFIRMED — no Discord access this lane; class-Discord pin read stays open).
- r/WowUI "Twisted!" request thread https://www.reddit.com/r/WowUI/comments/1rd1prm/
  (demand CONFIRMED at listing level: Anniversary player wants dual-seal "Twisted!"
  popup — matches S7's success-text pattern; thread body NOT read).

## 5. Uncertainty ledger + do-not-retry list

- Wrath/Retail drops: OAK TWW ret (B4bPSRI_m, GSE-based, TWW-only) + any WotLK-tagged
  items sighted — excluded per scope, not carded.
- Bodies UNCONFIRMED (sighted, not scraped): NQ_O1D5ky + 0SCWuXniu (S1 variants),
  Beez parent y3EZtdRm9, Kaedin parent Fj5FjlAEq, Faelor Dynamic/Auras/Non-Core/
  Maintenance pieces, Surveillant Rotation Twister, Gaffaen V2.0.3 rpP7Xejei,
  SoC Proc-Sound (category listing), Reddit thread bodies, video contents.
- Layouts from listing text only (no shots): S3, S5, S10, S9.
- Do NOT re-try: no-wait wago scrapes (shell, twice confirmed — `waitFor: 8000` +
  `maxAge: 0` is the recipe); firecrawl_search on this deployment (invalid body);
  firecrawl_agent with non-schema keys (keep bodies to url/formats/waitFor/maxAge);
  searxng during throttle windows (websearch carries); luxthos.com preview PNGs
  (promo banners, viewed); curl of wago search pages (JS shell, 3100 B, zero slugs).
- In-client behavior of every WA UNCONFIRMED throughout (offline research only).
- Nothing copied: no import strings, no code, no assets — links + viewed-layout
  descriptions only.
