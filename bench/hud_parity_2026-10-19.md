# HUD parity audit 2026-10-19 — every class vs the hunter/shaman bar

Desk: read-only parity audit (no code touched). Method: read `classes/*.lua`
HUD_SLOTS + `get_hud_state` + visuals builders + `hud.lua` contract + `hunter_ui.lua`
trackers on disk; cite slot tables + provider lines. No new pins, no mutations
(no behavior changed). Validation owner: orchestrator. In-client visuals UNCONFIRMED.

Scope: slot completeness, queue tints, cooldown swipes, OOM/mana awareness,
totem/tracker coverage, design-mode preview. Per class (rogue, paladin, warrior,
druid + hunter/shaman as the bar). Out of scope: addon/test edits (cleave lane +
3 running lanes own code).

## 0. The bar — what hunter + shaman HUDs have (union)

Slot completeness:
- HUNTER `classes/hunter.lua:1760-1770` 9 slots (steady/raptor/kill_command/multi/
  bestial_wrath/rapid_fire/aimed + trinket1/2); Era pick `:1771-1781` filters
  steady/kill_command/bestial_wrath → 6 live (guide/guide-HUD never disagree).
- SHAMAN `classes/shaman.lua:3072-3080` 8 slots (stormstrike/flameshock/weave/
  firenova/earthshock/twist + trinket1/2); guide grew to 13
  (`:3029-3034` + feralspirit/fireele/magma/lavalash/shamanisticrage/
  chainlightning/moltenblast) with NO mirror — deferred by design
  (`:3057-3060` + `tests/hud_state.lua` eight-slot pin, needs hud+options lane).

Cooldown swipes (both):
- Real CD via localized-name `GetSpellCooldown` + 1.51 s GCD-echo filter; missing
  reading = ready. Hunter `:1847-1860`, shaman `:3157-3167`.
- Fallback table while no real CD runs: hunter `:1811-1819`
  (steady 0/raptor 0/KC 60/multi 10/BW 120/RF 300/aimed 6); shaman `:3125-3132`
  (SS 10/FS 6/weave 0/FN 15/ES 6/twist 0).
- GCD swipe on ready slots: hunter all but BW/RF (`HUD_SKIP_GCD`
  `:1824-1827`, branch `:1901-1908`); shaman all (`HUD_SKIP_GCD = {}`
  `:3137`, branch `:3208-3216`). HUD 2 s rule hides GCD text (`hud.lua:99`).

Queue tints (hunter half of the bar; shaman has none — no on-next-attack kit):
- Hunter queued bar colors `classes/hunter.lua:580-586` (raptor/steady queued →
  `set_bar_color`; cleared `:552-555`). Shaman: no queue tint by design.

OOM / mana awareness (both + hunter extras):
- Mana tint: `hud_no_mana` via `IsSpellUsable` 2nd return, gated
  `db.hud_mana_tint`. Hunter `:1862-1869` + `:1911-1914`; shaman `:3169-3176` +
  `:3218-3221`. Paint is blue (`hud.lua:993-996`).
- Range tint: `IsSpellInRange == 0`, gated `db.hud_range_tint`. Hunter
  `:1871-1883` + `:1915-1917`; shaman `:3178-3190` + `:3222-3224`. Paint is red
  (`hud.lua:997-1000`).
- Hunter extras: KC ready-in-combat glow `:1919-1921`; ISS banked-proc glow on
  steady/aimed (`db.hunter_iss_badge_enabled == true`, `:1923-1933`); OOM Viper
  `VIPER` badge `ST.HUNTER.OOM_VIPER_FRAC = 0.05` + `get_oom_viper_prompt`
  (`:857-875`), rendered `hunter_ui.lua:1160-1214` (option-gated
  `hunter_oom_viper_badge_enabled ~= true` hides; unknown mana/Viper never prompts);
  mana fraction `get_mana_fraction` (`:843-856`); LnL badge (`:1219+`,
  `hunter_lnl_badge_enabled`).
- Shaman extras: `mana_fraction` input (`:2788-2797`, SR/ES gates); SS ready glow
  (`:3226-3228`); tracker badges SS/SR text (`setup_weave_visuals`
  `:1303-1321`); shield-charge rects (`:1323-1336`); windfury ICD strip
  (`:1244-1260`); FS bar + final-seconds glow (`:1262-1301`, `:1622-1658`);
  Stormstrike glow widget (`:1666-1748`).

Totem / tracker coverage:
- Hunter (`hunter_ui.lua` header `:1-31` + builders): cast bar + hidden Auto-Shot
  window + latency slice + clip tint + movement-safe zone (`:102-107`);
  4-state range helper strip (`:46-47,68-73`, `create_range_helper :230-238`,
  update `:828-886`); Rapid Fire aura bar (`:48-51,64`, `:240-262`, `:887-976`);
  aspect icon (`:53,78-83`, `:264-270`); BW duration + Frenzy stacks badges
  (`:84-101`, `:323-417`, `:978+`); ToT `>> TARGETING YOU <<` label
  (`:108-116`, `:304-321`, `:792-826`); weave prog (opt-in, `:999-1091`
  in classes/hunter.lua); shot log/report (post-fight, practice_ui).
- Shaman (`setup_weave_visuals :1211-1341` + refresh fns): weave breakpoint
  marker + top/bottom icons (`:1215-1235`); cast spark + OH mirror
  (`:1237-1242`, `:1339+`); windfury strip (`:1244-1260`); FS bar/glow/label
  (`:1262-1301`); SS/SR badges (`:1303-1321`); shield rects (`:1323-1336`);
  totem reconciliation — twist/air-slot (`refresh_twist_from_totems :844-864`),
  magma/fire-slot (`:918-941`), searing/fire-slot (`:943-970`), fireele guard
  (`:906-929` + gather `:2900-3004`); totem-drop commits on SUCCEEDED
  (`:1031-1076`); haste/MW/flurry scan (`:563-730`).

Design-mode preview (shared bar weakness):
- `HUD.preview_state` (`hud.lua:1025-1063`): scripted looping samples ONLY for
  `cs`, `consecration`, `exorcism`, `wings` + trinkets (`:1030-1058`); every
  other key returns nil → caller paints live state (`:1085-1094`). Hunter and
  shaman slots therefore demo nothing in design mode — same for rogue/warrior/
  druid. Paladin is the ONLY class with scripted previews (beats the bar).

Trinket tracker: shared `hud.lua` (`:257+`, `:365+`), no per-class gap.

## 1. Rogue — HAVE / MISSING vs bar

HAVE (cite):
- 13 slots `classes/rogue.lua:1034-1057` (snd/rupture/ea/ar/bf/tea/kick +
  kidney/restealth/bandage/coldblood + trinket1/2) — broadest set on the tree.
  kidney/restealth/bandage/coldblood hide unless toggle reads exactly true
  (`:1043-1054`, `:1215-1235` gate) = nil-off, no default-visible change.
- Aura slots (snd player-HELPFUL, rupture/ea target-HARMFUL, ar/bf buff-outranks-CD
  + stacked ≥2 yellow glow, restealth buff-outranks-CD) `:1074-1091`,
  `:1128-1157`, `:1159-1166`, `:1250-1265`.
- Cooldown slots (ar/bf fallback, kick/kidney melee-range tint, tea item-CD-outranks-spell
  + count grey-at-zero, bandage item-CD-outranks-spell + count, coldblood):
  `:1093-1109`, `:1167-1200`, `:1202-1214`, `:1241-1248`, `:1266-1294`, `:1215-1229`.
- Poison reminder text (presence booleans only, no charges)
  `:1359-1366`, `:1405-1424`; tick spark + pooling wash + Era SS band + swap band
  (`setup_rogue_visuals :1305-1369`, drivers `:1480-1574`).

MISSING vs bar:
- R-1 (HIGH, only contract-level gap on the tree): NO GCD swipe. Every other
  provider borrows the running GCD on ready slots — hunter `:1901-1908`,
  shaman `:3208-3216`, paladin `:3555-3563`, warrior `:3141-3149`, druid
  `:2215-2223`. Rogue `hud_cooldown_state` (`:1095-1109`) reports only the
  ability/item CD + `usable=false`; `get_hud_state` branches (`:1111-1298`)
  never call a `hud_gcd_remaining`, and the file contains zero `hud_gcd` /
  `SKIP_GCD` / cooldown-`FALLBACK` symbols (grep: only color fallbacks
  `:123-127`, `:1480-1574`). Ready rogue icons sit static while every bar
  sibling sweeps the GCD. Build spec §3 R-1.
- R-2 (parity note, N/A by kit — NOT a build item): no queued-ability bar tint.
  Hunter has raptor/steady (`hunter.lua:580-586`), warrior HS/cleave
  (`warrior.lua:771-787`), druid maul (`druid.lua:371-381`); rogue has no
  on-next-attack spell, so the pooling wash + tick spark (`rogue.lua:1320-1327`,
  `:1310-1318`) IS its queue-equivalent. No icon tint owed.
- R-3 (parity note): no banked-proc HUD glow. Hunter ISS glows steady/aimed
  while banked (`hunter.lua:1923-1933`); rogue ar/bf glow only while the BUFF
  rides + stacked (`rogue.lua:1137-1151`). No rogue banked-proc source exists
  in `gather_guide_inputs` (no ISS/MW equivalent), so nothing to tint — filed
  as observation, no spec.
- R-4 (parity note): no OOM badge. Hunter OOM Viper (`hunter.lua:857-875` +
  `hunter_ui.lua:1160-1214`); rogue energy is modeled by `usable=false` blue
  (ungated provider `:1104-1107`, paint-gated `hud.lua:993-996`) + tea/bandage
  zero-count grey (`:1193-1198`, `:1286-1293`). Correct for the kit; no badge owed.
- Design preview: NO gap vs bar (both unscripted → live state). Paladin beats both.

## 2. Paladin — HAVE / MISSING vs bar

HAVE:
- 7 slots `classes/paladin.lua:3375-3383` (cs/judgement/consecration/exorcism +
  trinket1/2 + wings) — archive set, byte-identical icons.
- Real swipes practice-aware: CS 6 / judge 8 / consec 8 / exo 15 / wings 180
  (`hud_ability_cooldown :3442-3502`); GCD on all but judgement/wings
  (`:3555-3563`, archive rule); mana + range tints gated (`:3565-3571`);
  judgement greys seal-less (`:3573-3577`); exorcism greys + glows vs
  Undead/Demon (`:3528-3538`, `:3578-3584`); wings ready glow (`:3585-3587`).
- Trackers BEAT the bar in depth: twist window band + success text (`:861+`,
  `setup_twist_visuals :1404-1473`); judgement marker (`:1066-1101`); reseal
  marker (`:1103-1145`); seal icons with aura swipes (`:1147+`,
  `setup_seal_icons :1476+`); JotC bar (`setup_jotc_bar :2442+`); CD icon row
  (`setup_cd_icons :2624+`).

MISSING vs bar:
- P-1 (HIGH, largest guide→HUD mirror gap on the tree): guide has 10 slots
  (`:3226-3279`: cs/soc/sob/twist/judge/consecration/exorcism/how/holy_shock/
  aura_mastery) but HUD mirrors only the archive 4 + wings (`:3375-3383`).
  Shaman gap is 13→8 with a deferral pin (`shaman.lua:3057-3060`); hunter Era
  pick is intentional (`hunter.lua:1771-1781`); paladin has NO deferral pin for
  soc/sob/twist/how/HS/AM. The SoC-rank-1, seal-maintenance, stopattack,
  prepull, hard-wait advisories are already filed as engine-only
  (`:3011-3038`, `:3331-3338`). Build spec §3 P-1.
- P-2 (parity note, N/A by kit): no queued-ability bar tint (no on-next-attack
  kit; nothing like hunter `:580-586` owed).
- P-3 (parity note): no OOM badge. Mana thresholds exist
  (`mana_consecration/exorcism_threshold :3056-3057`, `get_guide_mana_pct`
  `:2074+`) + `twist_mana_threshold` groundwork (`:3020-3029`, option filed);
  no VIPER-style badge like hunter (`hunter_ui.lua:1160-1214`). Filed with the
  options lane (widget + default), not a HUD-provider gap.
- Preview: paladin BEATS the bar (only scripted samples `hud.lua:1047-1058`).

## 3. Warrior — HAVE / MISSING vs bar

HAVE (at bar, no HUD-contract gap):
- 8 slots family-split `classes/warrior.lua:2929-2957` + `resolve_guide_slots`
  `:2965-2989` (TBC/Era/Wrath-fury op/execute/slam/hs/bt/ww; else
  op/execute/slam/hs/cleave/hamstring `hud_slot_hamstring :2936`; arms
  rend/ms/bladestorm `:2940-2944`; SoD execute/slam/hs/bt/ww/raging_blow
  `:2945-2946`; + trinkets). Guide↔HUD re-picked together — same discipline as
  hunter Era pick.
- Real swipes BT 6 / WW 10 / MS 6 / bladestorm 90 / raging 8, rest GCD-only
  (`HUD_COOLDOWN_FALLBACK :3020-3033`); GCD on ALL slots (`HUD_SKIP_GCD = {}`
  `:3038`, branch `:3141-3149`); rage-as-mana + range tints gated
  (`hud_no_mana :3070-3077`, `hud_out_of_range :3094-3106`, applied
  `:3151-3157`); OP dodge-window glow + usable-fallback (`:3079-3092`,
  `:3159-3176`); Execute health-gated ready glow (`hud_execute_range :3108-3122`,
  `:3177-3180`).
- Queue tints AT hunter bar: HS/cleave queued + insufficient-rage bar colors
  (`set_bar_color :758-787`, state `:387-417`, cleared `:738-744`).
- Trackers BEAT the bar: Shield Block bar (`setup_warrior_visuals :1550+`,
  `:1556+`); Slam cast bar (`on_spellcast_event :1460-1480`); OP proc flash;
  Rampage upkeep badge (`:1023-1065`); Battle Shout badge (`:908+`); W1 bank cue
  (`:1066-1084`); desync spark (`:869-874`).

MISSING vs bar: NONE on the HUD contract. Deltas are N/A-by-kit notes:
- No banked-proc HUD tint beyond OP window (ISS equivalent N/A — no banked-proc
  source in gather). No OOM badge (rage kit; bank cue + floor cover it). No
  range-helper strip / totem reconciliation (N/A). Design preview: same shared
  gap as bar (no samples → live state).

## 4. Druid — HAVE / MISSING vs bar

HAVE:
- 10 slots `classes/druid.lua:1970-1981` (maul/mangle/rip/rake/bite/shred +
  tf/berserk + trinket1/2); TF/Berserk liveness-gated
  (`tf_slot_live :2033-2045`, `berserk_slot_live :2047-2060`, applied
  `:2200-2207`; SoD-rune basis `:2052-2054`); runeless-Era Mangle hide
  (`:2194-2197`).
- Rotationals GCD-only + TF/Berserk real CDs, GCD skipped for TF/berserk
  (`HUD_SKIP_GCD :2119-2124`, branch `:2215-2223`, fallback `:2108-2117`);
  mana + range tints gated (`:2225-2231`); maul-una affordable grey
  (`:2233-2235`); TF/berserk ready-in-combat glow (`:2236-2240`).
- Queue tint AT hunter bar: maul queued + insufficient-rage (`:351-381`,
  state `:112-129`, cleared `:324-328`).
- Trackers BEAT the bar: energy tick bar (`:759+`, driver `:777+`); form label
  (`:451+`); Mangle/Rip/Rake debuff bars (`:430-432`); D5 Shred countdown
  (`:14-16`); D6 rage-at-cap badge (`:135-190`); Omen glow (`:16-17`,
  `:567-568`); GCD-tick overlay; pips (`:14`, `:467-468`).

MISSING vs bar:
- D-1 (only gap): Claw has a guide slot (`guide_slot_claw :1598`, in
  `ST.DRUID.guide :1916-1918`) but NO HUD slot — stated in-tree (`:1944-1946`
  "Claw has a guide slot but no HUD slot yet (its rule files its probe -
  filed follow-up)"). Hunter bar mirrors its base guide + aimed (`:1730-1754`);
  shaman defers 7 with a pin; druid's claw is the single unmirrored rotational.
  Build spec §3 D-1.
- Otherwise NONE: no OOM badge owed (rage/energy kit; D6 badge is the
  fight-readout equivalent); no totem reconciliation owed (N/A); design preview
  same shared gap as bar.

## 5. Hunter / shaman as the bar — residual notes (not gaps vs themselves)

- H/S-1 (shared, vs paladin only): hunter + shaman HUD slots have NO scripted
  design-mode samples (`hud.lua:1025-1063` covers only cs/consecration/exorcism/
  wings/trinkets). In `/st design` with `hud_locked == false` their rows paint
  live state (`:1085-1094`), not the looping demo paladin icons get. If the bar
  must demo-loop, the build lane extends `PREVIEW_STATE` per §3 HS-1 (hud.lua
  + suite only, no class files).
- S-1 (already filed, restated for completeness): 7 Wrath/SoD guide slots
  (feralspirit/fireele/magma/lavalash/shamanisticrage/chainlightning/
  moltenblast) have no HUD mirror (`shaman.lua:3057-3060` deferral,
  `tests/hud_state.lua` eight-slot pin). Needs a lane owning hud.lua +
  hud_state + options together.
- H-1 (already filed): Era 6-slot pick (`hunter.lua:1771-1781`) is intentional
  (dead slots filtered); SoD shares the ERA token so the same pick covers it.

## 6. Build-ready specs (missing pieces only; validation owner: orchestrator)

R-1 rogue GCD swipe (HIGH — sole contract-level отставание):
- Contract: `hud.lua:42-65` provider fields (`remaining/duration/text_remaining`
  for the GCD window); paint already handles GCD text-hide (`hud.lua:99`).
- Input: copy `hud_gcd_remaining` verbatim (hunter `:1830-1841` / shaman
  `:3140-3151` / paladin `:3425-3436` read `self.gcd.expires` → `remaining,
  spell_length or duration or 1.5`).
- Shape: add `local HUD_SKIP_GCD = {}` (all rogue slots rotational; tea/bandage
  item-CDs ride the same GCD-borrow rule as hunter steady/raptor) + fallback
  note (no per-slot fallback needed — ready state borrows GCD, CD state carries
  the client duration, exactly hunter/shaman).
- Branch (insert before `return s` in each non-hidden path, or once after the
  key dispatch): `elseif not HUD_SKIP_GCD[key] then local g, gd =
  hud_gcd_remaining(self, now); if g > 0 then s.remaining, s.duration = g, gd;
  s.text_remaining = g end end` — must NOT fire while a real CD/aura剩余 paints
  (bar precedent: `on_cd` short-circuits first).
- Files: `classes/rogue.lua` ONLY (+ `tests/hud_state.lua` pins + options none —
  GCD follows the existing row, no toggle). Mutations: GCD-stamp nil → no swipe;
  GCD expired → no swipe; CD running → CD wins over GCD.
- Pins owed: reused-table clear already (`:1063-1069`); add GCD-borrow cases per
  slot family (aura slots snd/rupture/ea, CD slots kick/kidney/coldblood, item
  slots tea/bandage).

P-1 paladin guide→HUD mirror (soc/sob/twist/how/holy_shock/aura_mastery):
- Descriptors (append after wings, before trinkets to keep trinkets last —
  rogue coldblood precedent `:1050-1054`): `{ key="soc", title="Seal of Command",
  kind="spell", spell=20375 }`, `{ key="sob", ... spell=<guide_sob_spell_id> }`,
  `{ key="twist", title="Twist", kind="spell", spell=20375 }`,
  `{ key="how", title="Hammer of Wrath", kind="spell", spell=<guide_how_spell_id> }`,
  `{ key="holy_shock", title="Holy Shock", kind="spell", spell=20930 }`,
  `{ key="aura_mastery", title="Aura Mastery", kind="spell", spell=407624 }`
  (ids from guide slots `:3228-3278`; art is rank-invariant, reads name-based).
- Provider: aura-shape for soc/sob (seal-expiry swipe like `update_seal_icons`
  `:1147+`); twist = composite ready glow (engine `twist_call`); how/HS/AM =
  `hud_ability_cooldown` + ready glow (wings rule `:3585-3587`); HS/AM
  unknown-hide (no signal → hidden, shockadin pattern `:3214-3216`).
- Gates: nil-safe (`== true` shows for HS/AM/SoD shapes; base soc/sob/twist/how
  follow family liveness like TF/Berserk `:2200-2207`); no default-visible
  change without explicit gate (standing rule).
- Files: `classes/paladin.lua` + `tests/hud_state.lua` (count + per-slot pins)
  + `option_tables.lua`/`config_presets.lua` (`hud_show_<key>` defaults, nil =
  off for HS/AM) + `nextaction_ui.lua` mapping IF the guide frame must also show
  them (filed R-1 in perclass verify §7 — same out-of-scope coupling as
  shaman SH-1). Mutations: unknown spell → hidden; toggle nil → hidden (HS/AM);
  seal down → grey (judgement rule `:3573-3577` shape).

D-1 druid claw HUD slot:
- Descriptor: `{ key = "claw", title = "Claw", kind = "spell", spell = 9850 }`
  (guide id `:1598`; UNCONFIRMED rank table — same caveat as mangle/bite/shred
  `:1953-1955`, confirm via GetSpellInfo in-client).
- Provider: rotational shape (GCD borrow + mana/range tints, no SKIP entry) —
  verbatim `maul..shred` path (`:2208-2231`).
- Files: `classes/druid.lua` + `tests/hud_state.lua` (10→11 pin + claw live/hide
  cases) + options (`hud_show_claw`, nil = off until the follow-up lane wires
  the widget — rogue R-T3 precedent `hud_templates §6`).
- Mutations: spell unknown → hidden-or-GCD per provider; toggle nil → hidden.

HS-1 (optional, bar demo-loop — hud.lua + suite ONLY, no class files):
- Extend `HUD.preview_state` (`hud.lua:1025-1063`) with looping samples for the
  bar keys that lack them: `steady/raptor/kill_command(multi 10 s loop)/
  aimed(6 s loop)/stormstrike(10 s loop)/flameshock(6 s loop)/weave(GCD-only)/
  firenova(15 s loop)/earthshock(6 s loop)/twist(GCD-only)` + rogue/warrior/druid
  keys if the lane wants full parity with cs (`:1047-1052` shape: `loop = now %
  N; s.start/duration/remaining/text_remaining/desaturate`).
- Unknown keys keep returning nil (live state fallback `:1059-1061` preserved).
- Pins: `tests/hud_state.lua` preview cases (sample loops, nil-fallback for a
  bogus key). No default-visible change (preview only while unlocked `:1079`).

## 7. Verdict table

| Class | Slots (HUD / guide) | GCD swipe | Queue tint | Mana+range | Ready/proc glow | OOM badge | Tracker set | Preview | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| Hunter (bar) | 9 (Era 6) / base 6 + Era/Wrath/SoD/Forever sets | yes (skip BW/RF) | raptor/steady bar color | yes + ISS + KC | KC + ISS | VIPER + LnL badges | cast/range/RF/aspect/BW/Frenzy/ToT | live-only | BAR |
| Shaman (bar) | 8 / 13 (7 deferred w/ pin) | yes (all) | N/A (no kit) | yes + SS | SS | none (mana_fraction only) | weave/totems/shields/badges | live-only | BAR |
| Rogue | 13 / 7+ | MISSING (R-1) | wash/tick (equiv) | blue-via-usable + counts | stacked ar/bf only | none (N/A) | tick/pool/SS/swap/poison | live-only | 1 build item |
| Paladin | 7 / 10 (6 unmirrored, P-1) | yes (skip judge/wings) | N/A (no kit) | yes + thresholds | wings/exo | none (filed) | twist/seal/JotC/CD | SCRIPTED (beats bar) | 1 build item |
| Warrior | 8 family-split / family sets | yes (all) | HS/cleave + rage | yes (rage) + bank | OP + Execute | none (N/A rage) | block/slam/Rampage/BS/desync | live-only | AT BAR |
| Druid | 10 / 7 (claw unmirrored, D-1) | yes (skip TF/Berserk) | maul + rage | yes + maul-grey | TF/Berserk | none (N/A; D6 equiv) | energy/debuffs/D5/D6/Omen/pips | live-only | 1 build item |

Limitations: offline verification only. In-client timing, aura secrecy, totem-clock
reconciliation, and all TESTING.md visuals are UNCONFIRMED and belong to the owner
in-client test session. No code changed; no suites run by this lane (read-only).
