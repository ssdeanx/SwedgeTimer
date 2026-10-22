# bench/hud_templates_2026-10-19 — ready-made HUD layout templates (DESIGN ONLY)

Desk: templates-design. Date: 2026-10-19. No addon file touched; no code.
Single new file (confirmed absent via `ls` before write). Read-only sources:
`hud.lua` (contract), `design.lua` + `designmode.lua` (design machinery),
`classes/{paladin,warrior,hunter,druid,shaman,rogue}.lua` (HUD_SLOTS),
`config_presets.lua` (hud defaults), `bench/competitor_gaps_2026-10-19.md` §X2.

Evidence bar: CONFIRMED = read on disk with line cite. UNCONFIRMED in caps.
PROVISIONAL = touches class files the 5 mid-flight follow-up lanes
(warrior-followups, paladin-followups, hunter-followups, druid-followups,
rogue-followups — central journal rows 102-106) may still move; re-verify keys
after they land. In-flight edits were NOT graded.

## 0. What templates can and cannot change (existing contract only)

- Slot descriptor (frozen, `hud.lua:31-40`): `key` (toggle suffix
  `hud_show_<key>`), `title`, `kind` (`spell`|`trinket`), `spell`,
  `texture`, `inv_slot` (13|14). A template picks a VISIBLE SUBSET — it never
  invents slots. CONFIRMED `hud.lua:230-249` (`HUD.validate_slot`).
- Order is fixed: icons render in `HUD_SLOTS` declaration order
  (`hud.lua:467-471`). Templates CANNOT reorder without code — none propose to.
- Geometry knobs (all existing db keys, `hud.lua:125-129` LAYOUT_KEYS +
  `config_presets.lua:38-62` defaults): `hud_icon_size` (36), `hud_spacing`
  (2), `hud_orientation` (`horizontal`; `vertical` = column), `hud_scale` (1),
  `hud_match_bar_width` (false; when on + row, icon size is computed from the
  bar width — `hud.lua:636-644`), `hud_x/y` (0/-236), `hud_show_text`,
  `hud_glow_enabled`, `hud_desaturate`, `hud_mana_tint`, `hud_range_tint`,
  border/font keys. Templates use ONLY these.
- Graceful degradation (already shipped, templates rely on it, no new code):
  trinket slots with an empty slot hide outside design mode (`hud.lua:618-631`);
  provider-hidden slots (druid TF/Berserk without spell data, rogue gated
  slots) draw nothing and reserve no width (`hud.lua:645-651`, reflow
  `hud.lua:757-812`).
- Design-mode positioning already exists: the HUD registers as the "Cooldown
  HUD" element (`designmode.lua:628-651`), drag = live move through
  `apply_settings`, double-click = reset, `hud_locked == false` keeps the row
  visible for positioning (`hud.lua:596-599`).
- Preview engine already exists: when unlocked, every wanted icon paints
  `HUD.preview_state` looping samples (`hud.lua:1048-1067`). COVERAGE GAP
  (CONFIRMED by reading `hud.lua:1027-1043`): scripted samples exist ONLY for
  `cs`, `consecration`, `exorcism`, `wings`, and trinkets — every other slot
  key returns nil and falls back to live state. Template preview for other
  classes therefore shows live state, not a demo loop, unless the build lane
  extends samples (scoped in §4). In-client readability UNCONFIRMED.
- Snap guides already exist: `DM.register_template` (`designmode.lua:813-847`)
  + pure cell geometry `D.row_boxes` (`design.lua:281-304`). Templates MAY
  register row rhythms later (optional build item, §4).

## 1. Paladin (slots CONFIRMED `classes/paladin.lua:3076-3084`: cs, judgement, consecration, exorcism, trinket1, trinket2, wings)

- **P-T1 "Twist Core" (recommended default):** visible cs, judgement, exorcism,
  wings; hidden consecration, trinkets. Geometry: 36 / spacing 2 / horizontal /
  match OFF. Position: class default (under bar). Fits: SoD/TBC twist play —
  the three twist-relevant reads + AW pop in one glance; nothing else competes.
- **P-T2 "Full Ret + Trinkets":** all 7 visible. Geometry: match_bar_width ON
  / horizontal (size auto from bar width). Fits: raiders who want trinket
  on-use/proc/ICD swipes in the same row (X1 demand, §X2 precedent: packs
  consolidate rather than scatter).
- **P-T3 "Minimal":** cs + judgement only. Geometry: 28 / spacing 2 /
  horizontal / match OFF. Fits: bar-purists, small screens, Forever leveling
  where fewer spells exist.

## 2. Warrior (slot sets CONFIRMED `classes/warrior.lua:2817-2872`, family-split via `resolve_guide_slots` — PROVISIONAL, followups lane in flight)

- **W-T1 "Fury Core":** visible op, execute, bt, ww, hs (TBC/Era/Wrath-fury
  set); hidden slam, cleave, trinkets. Geometry: 36 / spacing 2 / horizontal /
  match OFF. Fits: fury rotation — OP window + execute range + BT/WW swipes.
- **W-T2 "Full + Trinkets":** whole family set + trinket1/2 visible.
  Geometry: match_bar_width ON / horizontal. Fits: players who track trinket
  ICDs alongside the rotation (Sno/W1 desync-spark precedent stays on the bar).
- **W-T3 "Arms / SoD" (family-conditional, PROVISIONAL):** Wrath-arms set
  {op, execute, rend, ms, bladestorm, hs}; SoD set {execute, slam, hs, ww,
  raging_blow}; trinkets on. Geometry: 36 / horizontal / match OFF. Fits:
  arms/SoD kits the base set does not cover. PROVISIONAL: arms/SoD toggle
  wiring is owned by the in-flight warrior-followups lane.

## 3. Hunter (slots CONFIRMED `classes/hunter.lua:1514-1524`: steady, raptor, kill_command, multi, bestial_wrath, rapid_fire, aimed, trinket1, trinket2)

- **H-T1 "Shot Rotation":** visible steady, multi, aimed, kill_command; hidden
  raptor, pops, trinkets. Geometry: 36 / spacing 2 / horizontal / match OFF.
  Fits: TBC shot core; KC glow-when-ready is the built-in tell
  (provider `classes/hunter.lua:1626+` region).
- **H-T2 "Full BM + Trinkets":** all 9 visible. Geometry: match_bar_width ON /
  horizontal. Fits: BM with BW/RF pops + trinket ICDs in one row.
- **H-T3 "Minimal + Glow":** steady + kill_command only. Geometry: 28 /
  spacing 2 / horizontal / match OFF. Fits: minimal UI; KC glow carries the
  only decision.

## 4. Druid (slots CONFIRMED `classes/druid.lua:1882-1893`: maul, mangle, rip, rake, bite, shred, tf, berserk, trinket1, trinket2; tf/berserk provider-hide without spell data — `classes/druid.lua:1934-1961`)

- **D-T1 "Bleed Core":** visible mangle, rip, rake, shred; hidden maul, bite,
  tf, berserk, trinkets. Geometry: 36 / spacing 2 / horizontal / match OFF.
  Fits: cat bleed upkeep — the four DoT/shred reads, no pop noise.
- **D-T2 "Full Feral + Pops":** all 10 visible (tf/berserk auto-hide where the
  client lacks them; reflow closes the gap). Geometry: match_bar_width ON /
  horizontal. Fits: full cat + TF/Berserk ready-glow cues.
- **D-T3 "Bear Guard":** visible maul, mangle, berserk, trinket1/2.
  Geometry: 32 / spacing 2 / horizontal / match OFF. Fits: bear tanks (maul
  unaffordable-grey is the built-in tell). Bear-slot fit UNCONFIRMED
  in-client — no bear-tank source in corpus.

## 5. Shaman (slots CONFIRMED `classes/shaman.lua:2844-2853`: stormstrike, flameshock, weave, firenova, earthshock, twist, trinket1, trinket2)

- **S-T1 "Twist Core":** visible stormstrike, flameshock, earthshock, twist;
  hidden weave, firenova, trinkets. Geometry: 36 / spacing 2 / horizontal /
  match OFF. Fits: totem-twist enhance — SS/FS/ES + WF-totem skeleton.
- **S-T2 "Full Enhance + Weave":** all 8 visible. Geometry: match_bar_width ON
  / horizontal. Fits: LB weaving + Fire Nova AoE + trinket ICDs.
- **S-T3 "Minimal":** stormstrike + flameshock only. Geometry: 28 / spacing 2 /
  horizontal / match OFF. Fits: minimal UI / leveling.

## 6. Rogue (slots CONFIRMED `classes/rogue.lua:958-976`: snd, rupture, ea, ar, bf, tea, kick, kidney, restealth, bandage, trinket1, trinket2; kidney/restealth/bandage provider-hide unless their toggle reads exactly true — `classes/rogue.lua:966-970`)

- **R-T1 "UxkIny-style Core" (recommended default):** visible snd, rupture, ea,
  tea, kick; hidden CDs, utility, trinkets. Geometry: 36 / spacing 2 /
  horizontal / match OFF. Fits: every rogue; mirrors the UxkIny7oJ 2.4.3 pack
  curation (actives SnD/Rupture + poisons/CDs consolidated in one HUD —
  competitor_gaps §1.6) minus the energy ticker, which has no slot in the
  contract (R1 gap, still open — noted, not smuggled in).
- **R-T2 "Full + CDs + Trinkets":** +ar, bf, trinket1/2 visible.
  Geometry: match_bar_width ON / horizontal. Fits: CD-stacking play; Sno
  stacked-glow precedent (R3) lives in this row.
- **R-T3 "PvP Utility" (PROVISIONAL):** visible kick, kidney, restealth,
  bandage, ea. Geometry: 32 / spacing 4 / VERTICAL column (side-of-bar
  placement via design mode). Fits: PvP short-CD row (Sno short-CD tracker
  precedent, R3). PROVISIONAL: kidney/restealth/bandage have no option widgets
  and no `config_presets` defaults (CONFIRMED absent — `config_presets.lua`
  rogue block ends at `hud_show_kick`, lines 693-701); owned by the in-flight
  rogue-followups lane (icons/options). Template ships after that lane.

## 7. Preview / selection story (design; uses only shipped machinery)

- **Where:** each class's HUD options section gains one `hud_template` select
  (new widget — build scope, §4). Choices: the class's 2-3 names above +
  `Custom`. Default `nil` (= Custom): current behavior byte-identical, zero
  default-visible change (standing rule).
- **Preview:** picking a template writes its toggle + geometry set through the
  normal db keys and runs the existing `apply_settings` path (`hud.lua:653`);
  if the HUD is unlocked the row stays up and paints the looping samples for
  scripted keys (`hud.lua:1058-1067`) and live state elsewhere (§0 gap).
  Player then drags the frame in `/st design` to place it; double-click resets
  position only (template's slot/size set is untouched).
- **Pick:** selection persists in a new profile key (e.g. `hud_template`; new
  key — build scope); the applied db values are already profile-persisted by
  AceDB, so no other storage is needed. Any manual toggle/geometry tweak after
  picking flips the dropdown back to `Custom` (dirty-detect on the template's
  key set — build-scope logic, exact shape UNCONFIRMED until the options lane
  designs it).
- **Promise (Sno/UxkIny parity):** one click loads a whole curated look — the
  WA-pack benchmark from X2 (competitor_scan #15, still open) — without
  scattering widgets. Our single-row HUD already consolidates; templates are
  the curation layer packs provide.

## 8. Follow-up build scope (itemized; validation owner: orchestrator)

Shared machinery (once, not per template):
- `option_tables.lua`: per-class `hud_template` select widget + apply handler
  (nil-safe reads; explicit user action only — no default-visible change).
- `config_presets.lua`: per-class template tables (slot on/off sets from §§1-6
  + geometry values) + `hud_template = nil` default.
- `tests/hud_templates_state.lua` (new): every template references only keys
  present in that class's `HUD_SLOTS`; every key maps to an existing
  `hud_show_<key>` default (ROGUE R-T3 keys exempted until the followups lane
  lands — test asserts the exemption list, not the keys); geometry values
  within sane ranges (size 8-64, spacing 0-16, orientation enum); nil-safe
  apply. Mutation: drop/rename one slot key → suite fails.
- Optional (deferrable): extend `HUD.preview_state` samples beyond
  cs/consecration/exorcism/wings/trinkets so previews demo-loop for all
  classes; register `DM.register_template` row rhythms for the Full
  (match-width) rows. Mark anything beyond `hud.lua`'s contract UNCONFIRMED.

Per-class apply tables (the build lane's input — slot keys × geometry):
- Paladin: P-T1 {cs, judgement, exorcism, wings} 36/horiz/match-off;
  P-T2 all-7 match-on; P-T3 {cs, judgement} 28/horiz/match-off.
- Warrior (PROVISIONAL): W-T1 {op, execute, bt, ww, hs} 36; W-T2 family-full +
  trinkets match-on; W-T3 family-conditional arms/SoD sets 36.
- Hunter: H-T1 {steady, multi, aimed, kill_command} 36; H-T2 all-9 match-on;
  H-T3 {steady, kill_command} 28.
- Druid: D-T1 {mangle, rip, rake, shred} 36; D-T2 all-10 match-on;
  D-T3 {maul, mangle, berserk, trinket1/2} 32.
- Shaman: S-T1 {stormstrike, flameshock, earthshock, twist} 36; S-T2 all-8
  match-on; S-T3 {stormstrike, flameshock} 28.
- Rogue: R-T1 {snd, rupture, ea, tea, kick} 36; R-T2 +{ar, bf, trinkets}
  match-on; R-T3 (PROVISIONAL) {kick, kidney, restealth, bandage, ea}
  32/vertical/spacing-4.
- No new widget API was assumed: every geometry value above maps to an
  existing LAYOUT_KEYS entry (§0). Anything else the build lane wants is
  UNCONFIRMED until cited against `hud.lua`.

## 9. Uncertainty ledger

- All slot sets CONFIRMED on disk at the cited lines; family-conditional
  warrior sets + rogue utility slots are PROVISIONAL per the 5 in-flight
  lanes — re-verify `HUD_SLOTS` keys and `hud_show_*` defaults after they land.
- Template fit ("when each fits") is design judgment against rotation shapes,
  not sim output; in-client readability UNCONFIRMED throughout.
- `Custom` dirty-detect shape UNCONFIRMED (options-lane design).
- Validation owner: orchestrator.
