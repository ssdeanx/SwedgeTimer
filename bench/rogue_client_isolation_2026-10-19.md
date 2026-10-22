# bench/rogue_client_isolation_2026-10-19 — rogue class isolation + per-client correctness (READ-ONLY)

Desk: rogue-isolation. Date: 2026-10-19. No addon files touched; no code edits; no git.
Single new file per the dispatch brief. Subject (stable, read in full):
`classes/rogue.lua` (1451 lines), `rogue_guide.lua` (552 lines),
`tests/rogue_state.lua`, `tests/rogue_guide_state.lua` + shared-engine reference
`compat.lua`, `main.lua`, `nextaction.lua`, `nextaction_ui.lua`.
OUT files peeked for context only (claims from them marked PROVISIONAL, never findings):
`practice.lua` (drills), `hud.lua` (toggle semantics), `rotationtext.lua` (provider dispatch),
`config_presets.lua` + `option_tables.lua` (defaults/widgets), `druid_energy.lua` (dependency target),
`bars.lua`/`diag.lua` (hook/provider pins).

Evidence bar: every file:line below was read in-tree 2026-10-19. WoW-API shapes checked
against /home/sam/wow-ui-source with `git show <branch>:path` (checked-out branch is
`classic_era` 1.15.9.70003; versions sighted: `classic_era` 1.15.9.70003,
`classic_anniversary` 2.5.6.70006, `classic_titan` 3.80.2.69815, `live` 12.1.0.69814,
`origin/forever` 1.60.1.70374, `origin/classic` 5.5.4.70268). Anything not verifiable
offline is UNCONFIRMED in caps (in-client decides). Family key: ERA covers Classic Era
AND SoD (both report the ERA family token); TBC = Anniversary 2.5.6; WRATH = Titanforge
3.80.2; CATA/MISTS = classic-line inert-standin flavors; RETAIL = live 12.1.x;
FOREVER = WoW Forever 1.60.1 (Mainline-code, native PLAYER_SWING engine).

Prior corpus (extended, never re-derived): `bench/rogue_readiness_2026-10-19.md` §4
(post-fix constraints H1–H6/M1–M7/G1–G6/R4 + slices B–D),
`bench/competitor_gaps_2026-10-19.md` §Rogue (R1 proc-aware tick, R2 poison reminder,
R3 short-CD row + stacked glow), `bench/rogue_deep_2026-10-19.md`
(SS-after-swing Era-CONFIRMED/TBC-refuted, Yam corrector, Sno teardown),
`bench/rogue_erroraudit_2026-10-19.md` (8 findings, ADEQUATE).

## 0. Verdicts (orchestrator summary)

- Cross-class refs: **1 runtime-reached (F1 HIGH)**, 1 harness-scope (F2 LOW),
  comment-only mentions (F3 INFO, no action), everything else verified absent (F4).
  Known lead CONFIRMED: rogue TTD reads `st.druid_energy` in-tree
  (`classes/rogue.lua:504`; header `:30`; test pin `tests/rogue_state.lua:679-680`).
- Per-client cells failing (proven broken offline): **0**. 70 cells graded
  (10 features × 7 families); posture is active/inert/hidden-with-reason throughout,
  fail-safe direction (unknown hides) holds on every cell.
- UNCONFIRMED ledger: **16 items** (in-client decides; failure modes are
  feature-dead/hidden, never wrong advice — except ledger #7, contained by default-off).

## 1. Isolation findings (file:line + verdict + fix direction)

### F1 HIGH — runtime-reached cross-class call: `st.druid_energy`
- Lines: `classes/rogue.lua:504` (`local de = st.druid_energy`), `:540`
  (`de.TTD_SAMPLE_SECONDS`), `:547-548` (`de.update_hp_velocity`), `:542`
  (`de.get_time_to_die`). Reachability: **runtime-reached** — `gather_guide_inputs`
  calls `ST.ROGUE.get_time_to_die` every guide tick (`classes/rogue.lua:694`);
  the `st.druid_energy` table read executes on every call, the EMA helpers on every
  target-present tick. Not guarded by nil-module fallback (a missing module returns
  nil TTD silently — safe shape, but still a cross-module read on the hot path).
- Documented in-tree: header `classes/rogue.lua:30` ("TTD via the druid D4 EMA"),
  `:498` ("same maths as classes/druid.lua's D4 sampler, via st.druid_energy"),
  test pin `tests/rogue_state.lua:679-680` (asserts the reuse — the pin entrenches
  the coupling, it does not justify it).
- Why it violates constraint 2: EACH CLASS MUST HAVE ITS OWN FUNCTIONS. The rogue
  hot path dereferences another class lane's runtime table; `druid_energy.lua` is
  explicitly OUT (in-flight writer lane owns it) — a writer-lane refactor (rename,
  rescale, remove) breaks rogue TTD at runtime with no load-time error (nil table
  → silent nil TTD → finisher rules fall through to pool; degraded, not loud).
- Fix direction (duplicate small pure logic into the owning class, never cross-call):
  vendor the three pure pieces into rogue-owned space — `TTD_SAMPLE_SECONDS`-scale
  constant + EMA update + TTD divide — either as `ST.ROGUE.update_hp_velocity /
  ST.ROGUE.get_time_to_die` helpers in `classes/rogue.lua` beside the sampler, or
  as `st.rogue_guide` pure helpers in `rogue_guide.lua` (keeps the WoW-free
  discipline; sampler stays in the class module). Keep the M7 provenance rule
  byte-for-byte (own baseline only, never `enemy_swing` fallback) and the nil-TTD
  fallthrough. Then delete the `st.druid_energy` read; update the two test pins to
  assert module-local provenance (static pin: no `st.druid_energy` string in
  `classes/rogue.lua`; behavioral pins unchanged). Estimated blast radius: 1 file
  + 1 suite + header comments (`:30`, `:498`).

### F2 LOW — harness-scope coupling: sandbox loads another lane's module
- Lines: `tests/rogue_state.lua:442` (`"druid_energy.lua"` in the sandbox module
  list). Verdict: **test-harness only, not shipped runtime** — no finding against
  the addon. Fix direction (only if F1 lands): replace with a fixture-local EMA
  stub or drop the entry once the class module no longer reads it; the TTD
  behavioral pins (`tests/rogue_state.lua` §TTD/M7) are unaffected either way.

### F3 INFO — comment-only cross-class mentions (dead, no action)
- `classes/rogue.lua:30,498` (druid D4 precedent cites — doubles as F1
  documentation, the comments themselves are dead text), `:1396-1397` ("following
  the hunter's shape (ST.HUNTER.get_rotation_key in classes/hunter.lua:1337-1352)"
  — precedent cite, no code read), `:16` (rogue_guide band cite — own module),
  `:24,29` (api/lust cites — own/shared infra).
- `rogue_guide.lua` header: provider-ordering note (`:5-6` paladin/warrior/druid/
  shaman/hunter), `:66` (druid-D4-EMA reuse note — becomes stale if F1 lands,
  reword then), `:85,109` (druid rip/rake nil-rule precedent), `:174` (warrior
  Rend window precedent). All dead text documenting precedent, the permitted use
  of comments. No action; reword `:66` only as part of an F1 fix.

### F4 VERIFIED ABSENT — the rest of the cross-class surface (no action)
Each checked by grep over `classes/rogue.lua` + `rogue_guide.lua` (code lines only,
comments excluded):
- No `ST.<OTHERCLASS>` runtime reference (no `ST.WARRIOR/HUNTER/DRUID/PALADIN/
  SHAMAN` outside comments) — CONFIRMED absent.
- No `st.warrior_guide / st.hunter_guide / st.druid_guide / st.shaman_guide`,
  no `twist`, no `weave`, no `hunter_ui`, no `practice`/`practice_ui` calls —
  CONFIRMED absent. (Static pin opportunity: `tests/rogue_state.lua` already pins
  M7 enemy-cycle absence (`:675-678`); an `st.druid_energy`-absence pin is the F1
  mirror.)
- No `st.nextaction` (paladin decision engine) reads: `classes/rogue.lua:621,661,
  889` + `rotation` `:1438` read only `st.rogue_guide`; `grep st\.nextaction[^_]`
  returns nothing — provider isolation from the paladin decision model CONFIRMED.
  `rogue_guide.lua` touches only `st.rogue_guide` (own table); strict-sandbox load
  test (`tests/rogue_guide_state.lua:46-61`) errors on ANY global read — WoW-free
  CONFIRMED.
- No `st.is_mainline` / `st.is_retail` runtime gate in either file (`:35,:1341`
  are comments stating the deliberate absence — swing activity decides, per the
  standing rule) — CONFIRMED absent, correct: the Forever client must run these
  cues while Retail stays hidden via the never-swinging stand-in.
- No CLEU registration or handler (`ST.ROGUE.COMBAT_LOG_EVENT_UNFILTERED` pinned
  nil `tests/rogue_state.lua:611`; `main.lua:557` registers CLEU only for
  PALADIN/WARRIOR + non-mainline — rogue needs none: aura/power/CP reads only,
  R1 rule) — CONFIRMED absent on all families, including TBC Anniversary (no Shiv
  cast matching ships, so the Anniversary name-fallback requirement never triggers).
- No `on_spellcast_event / on_spellcast_succeeded / on_spellcast_failed_quiet`
  (`tests/rogue_state.lua:609-610` pins nil; `main.lua:1762` dispatch
  `if self[c].on_spellcast_event` no-ops) — CONFIRMED absent; the seven thin
  `UNIT_SPELLCAST_*` handlers (`main.lua:560-571`) exist on every family (event
  documented `classic_era:UnitDocumentation.lua:3286` and
  `origin/forever:UnitDocumentation.lua:4846`; Blizzard's own ActionButton
  registers it on both) but rogue correctly consumes nothing from them.
- Allowed shared infra (the single crossing points, not class code): `st.api`
  alias `classes/rogue.lua:59` (all client reads go through `compat.lua`);
  `st.family` (`:679,:1106` + pool-band/gather reads); `st.hud` + `st.nextaction_ui`
  (guarded `if st.<frame>` init/tick, `:1328-1336,:1363-1375` — inert-without-frame
  pinned `tests/rogue_state.lua:963-978`); `st.lust_supported` (`:572,:581`,
  compat-owned flag); `self:get_class_table / self:convert_color /
  self:get_visuals_frame / self:get_bar_visuals_width_and_height` (addon-base and
  bars-provided `self` methods, not class modules).

## 2. Per-client matrix

Legend: ACTIVE (runs/shows where reads answer) · SILENT (no band/rule for this
family — deliberate unknown-family posture, never a guess) · HIDDEN (gate fails:
toggle/family/loadout/unknown) · INERT (no engine/swing on this flavor).
SoD shares the ERA family token → ERA column covers SoD unless noted.

### 2.1 Tick predictor + spark (`update_energy_tick`, spark widget)
- ERA / SoD: ACTIVE. 2 s / 20-energy cadence is Era+TBC CONFIRMED bench corpus
  (`rogue_research` §§1.1/1.3 via readiness §2). Cap-advance arithmetic, Yam
  proc-immunity (15/25), H4 unknown-hides all hold. SoD rune-altered pacing is
  UNCONFIRMED (ledger #2) — failure mode is H4-hide, not wrong spark.
- TBC: ACTIVE (same CONFIRMED cadence).
- WRATH: ACTIVE with bands present; tick cadence itself UNCONFIRMED beyond
  Era/TBC (ledger #2). Fail-safe via H4.
- CATA / MISTS: predictor runs (no family gate — deliberate) but cadence is
  UNCONFIRMED and haste-scaling may drift it (ledger #15); H4 hides drift
  (missed-tick → anchor dropped, `classes/rogue.lua:459-464`). Spark shows only
  while a phase is actually observed.
- RETAIL: HIDDEN in practice. Smooth regen deltas never seed a phase (first +20
  never arrives in phase; unrecognized micro-grants latch unknown,
  `:430-433`); even a coincidental +20 seed self-corrects on the next smooth
  samples. No family gate needed — arithmetic decides. (In-client decides, ledger #2.)
- FOREVER: ACTIVE (assumes classic 2 s tick — UNCONFIRMED, ledger #2); same H4
  self-correction as Cata/Mists.
- API basis: `api.UnitPower(player,3)` + `UnitPowerMax` — PowerType 3=Energy,
  4=ComboPoints CONFIRMED identical on all branches
  (`classic_era` + `origin/forever` + `live` `:PowerTypeConstantsDocumentation.lua:28-29`;
  `UnitPower` doc `classic_era:UnitDocumentation.lua:1615`). CP reads (`:673`)
  same basis.

### 2.2 Pooling tint (wash; `pool_verdict` + `POOL_BANDS`)
- ERA / TBC / WRATH / FOREVER: ACTIVE (data-driven 65/85; options overrides
  `rogue_pool_band_pre/post` nil-fall back to family band, `rogue_guide.lua:463-465`).
  Band VALUES on ERA/WRATH/FOREVER are carried-from-TBC data — UNCONFIRMED
  (ledger #3); engine default 100-cap + tick-caps-you lines are family-independent.
- CATA / MISTS / RETAIL / UNKNOWN: SILENT (no band table → `pool_verdict` nil →
  wash hidden, evaluate rule 7 falls through — `rogue_guide.lua:190-194,528-531`).
  Deliberate unknown-family posture (never a guessed band); NOT a defect. RETAIL
  phase-pooling is documented intent (`rogue_research` §1.6).
- Toggle basis: `show_rogue_pool_tint=false` default (nil-safe `== true` show,
  `classes/rogue.lua:1183`) — default-off on every client (options gate is
  client-independent; no per-client divergence).

### 2.3 Era SS window (red band + "SS"; default-visible by owner order)
- ERA: ACTIVE when all four hold: toggle on (ships `true`, `config_presets.lua:603`),
  `st.family=="ERA"` exact equality (`classes/rogue.lua:1106`), post-MH window
  0.1–0.2 s (`:1119-1135`, engine-dead/is_full/nil-speed → false), confirmed sword
  mainhand (`:1105-1115`). SoD: same ERA token → shows; SoD validity UNCONFIRMED
  (ledger #8).
- TBC / WRATH / CATA / MISTS / RETAIL / FOREVER / UNKNOWN: HIDDEN by family gate
  (TBC-refuted per `rogue_deep` §1 — exact-equality gate is the correct shape,
  never a "non-TBC" test). CATA/MISTS additionally INERT via engine stand-in
  (no swing start → `in_post_mh_window` false).
- Loadout risk: subclass string `"Sword"` (`:1114`) is UNCONFIRMED — the only
  in-tree source is the module + its own sandbox fixture
  (`tests/rogue_state.lua:188`, self-mirroring, proves nothing about the client);
  no `GetItemInfo` subclass string table found in wow-ui-source offline
  (ledger #1). Failure mode is feature-dead (hidden), never a wrong band.
  Item-shape basis: `api.GetInventoryItemID(slot)` two-arg call matches Blizzard's
  own classic use (`classic_era:EquipmentManager.lua:88`); slots 16/17 are engine
  constants, sandbox-mirrored, UNCONFIRMED in-client (ledger #10).

### 2.4 Swap band + copy (`SWAP_CUE_FAMILIES`, "swap: GCD + swing reset")
- ERA / TBC / FOREVER: ACTIVE (same post-MH geometry + toggle
  `show_rogue_swap_cue=false` default). Wrath exclusion recorded
  (`classes/rogue.lua:95` + `rogue_deep` §5.4) — HIDDEN on WRATH by data, correct.
- CATA / MISTS: HIDDEN (no family key + stand-in engine). RETAIL: HIDDEN (no key;
  no reset mechanic to time). UNKNOWN: HIDDEN. Copy text carries cost
  (`:96`, `draw_window_band` geometry shared with SS band `:1264-1267`).

### 2.5 Poison reminder (presence only, charges deliberately out)
- ALL families: ACTIVE-when-enabled, HIDDEN by default
  (`show_rogue_poison_cue=false`, `config_presets.lua:607`). Presence via
  `api.GetWeaponEnchantInfo` positions 1/5: classic shape CONFIRMED on
  `classic_era`, `classic_anniversary`, `classic_titan`, `origin/classic`
  (`SecureGroupHeaders.lua:686,824` — hasMainHandEnchant pos 1, hasOffHandEnchant
  pos 5); live + forever use the `Deprecated_12_1_0.lua:44-66` shim preserving the
  same positions (12 values, 3 slots × 4; MH=1, OH=5). Non-boolean → nil → hidden
  (`compat.lua:1141-1153`); charges never consumed (probe shape UNCONFIRMED,
  `rogue_deep` §5.8 — ledger #4/5). Retail caveat: if Retail poisons never present
  as weapon enchants, an enabled cue false-alarms permanently — contained by
  default-off, in-client decides (ledger #7).

### 2.6 HUD slots (SnD/Rupture/EA/AR/BF/Tea/Kick + R3 Kidney/Re-stealth/Bandage + trinkets)
- ALL families with answering reads: ACTIVE once `hud_enabled` master is on
  (master ships off — `config_presets.lua` shared default; slot toggles ship on
  for the 9 teardown slots, `config_presets.lua:638-646`).
- R3 row (Kidney/Re-stealth/Bandage): HIDDEN unless its own toggle reads exactly
  `true` (`shortcd_wanted`, `classes/rogue.lua:334-340,962-967`); NO defaults ship
  (`config_presets.lua:569-646` has no `hud_show_kidney/restealth/bandage`) and NO
  option widgets ship (`option_tables.lua` grep negative) — the provider-level
  hide is the load-bearing no-default-visible gate because the HUD treats a nil
  toggle as wanted (`hud.lua:622-624`). Nil-safe on every client; PROVISIONAL:
  widget/policy ownership sits with the options lane (OUT).
- Slot-name resolution by name through client spell data (`apply_spell_ids`,
  `:186-215`); unresolved → slot skipped by `hud.lua` validation. Name-form
  `GetSpellInfo` acceptance per client is compat-inherited (global on classic per
  `classic_era:SharedUIPanelTemplates.lua:1407` id-form use; `C_Spell` docs on all
  branches) — in-client fill decides per name (cold-spellbook retry `:349-351`).
- Secret regime (Midnight/C_Secrets): absent aura → `hidden` (unknown), never
  greyed-missing (`:820-838,900-903,986-996`); probe `api.auras_may_be_secret`
  doc-present on ALL branches (`SecretPredicateAPIDocumentation.lua:113`
  classic_era, `:119` live/forever) but runtime-absent on classic per compat —
  in-client decides per family (ledger #9). Cooldown shape: `spell_cooldown`
  treats ≤1.51 s as idle (`:269`) — standard cross-class rule, no rogue-specific
  GCD risk. Range tint: `IsSpellInRange` nil=unknown→no tint (`:956-960,976-980`;
  `C_Spell` doc on all branches; classic global mapped by the live transition
  guide) — fail-safe.
- Trinket slots: HUD-served (`inv_slot` 13/14, `tests/rogue_state.lua:635-636`);
  provider returns the cleared table for them (`:1028-1029`).

### 2.7 Guide provider + gather (`ST.ROGUE.guide`, `gather_guide_inputs`, M6/M5)
- ALL families: ACTIVE once `nextaction_enabled` (ships `false`,
  `config_presets.lua:627`) + swing activity; OFF-default on every client
  (no per-client divergence — the gate is user opt-in after in-client verification).
- Frozen-contract conformance VERIFIED against `nextaction_ui.lua:13-82`: 7 slots
  with guide action keys (`:592-601`), caller-owned gather (`:604-606`),
  evaluate writing every frozen field every tick + `riding` + `inputs_unknown`
  (`:612-649`), labels POOL/NOW flowing through the frame's label selection
  (`nextaction_ui.lua:386,556-562` with HOLD/RIDE fallbacks).
- Unknown ownership (M6): unreadable energy/CP, secret-regime lust, or missing
  `st.rogue_guide` → `inputs_unknown=true` → frame "…" (`:763-775`,
  `tests/rogue_state.lua:853-937`). Lust canary reuses compat's confirmed ids
  2825/32182 (`:114`, `compat.lua:125`) + `st.lust_supported` (false on ERA/UNKNOWN
  → honest nil, never unknown, `:581-582`). No new probes — nothing to drift per
  client.
- RETAIL note: unlike the paladin engine's RETAIL short-circuit
  (`nextaction.lua:359-371`), the rogue engine has NO family short-circuit — on
  Retail it evaluates live reads (pool silent via nil band; Envenom `chain` rule
  live; finisher rules live off aura/CP reads through the `C_UnitAuras` wrapper
  `live:UnitAuraDocumentation.lua:188`). Aura-widget behavior on Retail is
  in-client-decides (ledger #14); swing-gated visuals stay hidden via the
  never-swinging stand-in.
- CATA/MISTS note: pool + Envenom SILENT (no data tables — deliberate, §2.2);
  EA-duty/Shiv/dying-dump/planned-finisher/Tea rules ACTIVE (family-independent;
  every rogue client has Rupture/Eviscerate per readiness F6). TTD feeds the
  decider only from the own-EMA (M7; `tests/rogue_state.lua:675-678` pins no
  enemy-cycle read) — F1 does not change provenance, only module ownership.
- Per-client Envenom table kept decoupled (ERA≠TBC tables even where fields
  coincide, `tests/rogue_guide_state.lua:104-107`) — a tuning pass cannot
  silently recouple families.

### 2.8 Rotation key (`ST.ROGUE.get_rotation_key`)
- ALL families: generic dispatch, no class branch (`rotationtext.lua:189-204` —
  PROVISIONAL, OUT file, read for context): provider present →
  `guide.gather+evaluate` → localized ability name (cached per spell id,
  falls back to raw action key), POOL text while holding, nil → empty label
  (`classes/rogue.lua:1436-1451`). No practice branch (Twist Practice is
  paladin-only, `:1402-1403`). Behaves wherever gather behaves; unknown → nil →
  hidden. No per-client divergence.

### 2.9 Practice drills (PROVISIONAL — `practice.lua` is OUT, read for context only)
- Two `class="ROGUE"` scenarios exist: `rogue_energy_pool`
  (`practice.lua:2554-2587`, 2 s tick marker + weave-band grading, nil-marker
  unscored) and `rogue_ss_window` (`:2635-2669`, 0.1–0.2 s offset grading,
  unreadable swing → nil). Both pure, nil-safe, family-agnostic; Era-only
  selection is the caller's job (`:2589-2596` comment). No grade of the OUT file;
  rogue-side posture (no practice branch in `get_rotation_key`) is consistent.

### 2.10 Options gates (context — defaults/widgets read, not graded)
- Shipped ROGUE defaults (`config_presets.lua:569-646`): all behavior toggles
  ship false/off except the owner-ordered red SS exception
  (`show_rogue_ss_window=true`, `:603` + gate comment `:599-602`); colors 0-255 +
  0-1 alpha; thresholds mirror engine defaults with nil-fallback in the engine.
  Nil-safe reads (`== true` show / `== false` hide) hold on every client; no
  default-visible change ships without the recorded gate.
- `ST.class_opts_funcs.ROGUE` exists (`option_tables.lua:4305`; widget list pinned
  `tests/rogue_state.lua:576-593`); R3 short-CD keys have no widgets (provider
  gate covers, §2.6). No per-client options divergence exists or is needed.

## 3. UNCONFIRMED ledger (in-client decides; orchestrator owns the test session)

1. GetItemInfo weapon-subclass exact string (`"Sword"`, `classes/rogue.lua:1114`).
   Only in-tree source is the module + its self-mirroring fixture
   (`tests/rogue_state.lua:188`); no subclass string table in wow-ui-source
   offline. Wrong string ⇒ Era SS window feature-dead (hidden, fail-safe).
   Check: `/dump select(6, GetItemInfo(<sword itemID>))` on Era.
2. 2 s / 20-energy tick cadence outside Era/TBC (WRATH/CATA/MISTS/FOREVER/SoD;
   RETAIL smooth regen expected-hidden). Only Era+TBC CONFIRMED (bench corpus).
   Cata+ haste-scaling and SoD rune pacing could drift the predictor; H4 hides
   drift. Check: Yam-overlay tick alignment per client.
3. Pool bands 65/85 on ERA/WRATH/FOREVER (carried-from-TBC data,
   `rogue_guide.lua:148-153`). Check: cap-timing feel per client.
4. `GetItemCount` / `GetItemCooldown` by item NAME ("Thistle Tea",
   "Heavy Netherweave Bandage") on each client — no FrameXML by-name proof found
   offline. Contained: nil=unknown, never zero (fail-safe). Check: Tea count/CD
   + Bandage count/CD per client.
5. Thistle Tea item usability/cooldown shape per client (`rogue_deep` §5.8).
6. R3 name mappings: "Kidney Shot" CONFIRMED (Sno list); "Vanish"→Re-stealth and
   "Heavy Netherweave Bandage"→Bandage UNCONFIRMED (generic Sno labels).
   Wrong name ⇒ slot hidden (fail-safe), never a wrong icon.
7. Retail poison-application mechanics vs `GetWeaponEnchantInfo` presence: if
   Retail never reports weapon enchants, an enabled cue false-alarms permanently.
   Contained by default-off; do NOT enable the cue on Retail before checking.
8. SoD SS-window validity (ERA token shows it; SoD rune/swing pacing unaddressed
   by the Era CONFIRM/TBC-refute pair).
9. `C_Secrets.ShouldAurasBeSecret` runtime presence/absence per family
   (doc-present everywhere: `SecretPredicateAPIDocumentation.lua:113`
   classic_era / `:119` live+forever; runtime-absent on classic per compat code +
   sandbox). Secret-regime HUD/guide hide-paths need a Midnight check.
10. Inventory slots 16/17 numeric (engine constants; sandbox-mirrored;
    two-arg `GetInventoryItemID("player", slot)` shape CONFIRMED
    `classic_era:EquipmentManager.lua:88`).
11. Rupture per-CP durations (only 1CP 8 s sourced, `rogue_research` §5.2;
    `rupture_min_ttd=8` default) — TTD-boundary tuning on all families.
12. EA refresh 3 s / Shiv 2 s / Tea 40 defaults (no rogue source; watch-list
    windows). Tuning, not correctness.
13. Stacked-glow counted set (AR+BF only — UNCONFIRMED beyond Sno's list,
    `competitor_gaps` R3).
14. Retail guide finisher prompts (Rupture/Eviscerate/Envenom-chain off
    `C_UnitAuras`-wrapped reads) — widgets-only posture, verify no false
    confidence through a secret regime.
15. Cata/Mists energy mechanics for the predictor (haste-scaled regen?) + TTD
    health reads; pool/Envenom silence is deliberate regardless.
16. Per-name spell resolution for all 14 slot/guide names on each client
    (cold-spellbook retry bounds the risk; in-client fill decides).

## 4. Tooling log

Code Mode only, no web. `read` in-tree for every anchor above; `grep` for the
F4 absence proofs (`ST.(WARRIOR|HUNTER|DRUID|PALADIN|SHAMAN)`, `st.nextaction[^_]`,
`is_mainline`, `COMBAT_LOG|on_spellcast` — code-vs-comment separated);
`s
...[truncated 1580 chars]