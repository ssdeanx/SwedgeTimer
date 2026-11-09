# rogue_readiness_2026-10-19 — Rogue sixth-class readiness audit (READ-ONLY)

Desk: rogue-readiness. No addon files touched. Single new file per
`bench/briefs/brief_rogue-readiness-audit_2026-10-19.md` (HELD flag lifted —
both fix lanes reconciled 2026-10-19).
Date: 2026-10-19. Tree state: harness 35/0, luacheck 2/0 (both fix-lane
buildouts agree).

Extends by pointer, never re-derives: `bench/rogue_research_2026-10-19.md`
(rotations/poisons/caps per client), `bench/rogue_deep_2026-10-19.md`
(SS-after-swing Era-CONFIRMED/TBC-refuted, speedrun tech, competitor teardown,
addon handoff table), `bench/feature_hunter_audit_2026-10-19.md` (H1–H6/M1–M7),
`bench/feature_proctor_audit_2026-10-19.md` (G1–G6), `bench/fix_guides_weave_2026-10-19.md`,
`desks/fix-engine/journal.md`, `desks/fix-guides/journal.md`, `bench/lessons.md`.

Evidence bar: every file:line anchor below was read in the fixed tree
2026-10-19. UNCONFIRMED marks in-client checks, not hedges.

## 0. What the two fix lanes changed (read this first)

fix-engine (main/bars/swing_source/enemy_swing + 4 state suites, 35/0, 8/8
mutations — `desks/fix-engine/journal.md` §2026-10-19 complete):
- H1 `main.lua:19-29` stub returns `nil,nil,nil`; `main.lua:630-646` sets
  per-hand `engine_dead`; `bars.lua:579-590,916-925` render dim + "engine
  offline". Rogue swing widgets must branch on `engine_dead`/nil speed, never
  on a plausible 1 s cycle.
- H2 `bars.lua:517-556` `run_guarded` isolates the class hook
  (`bars.lua:681`) and every zone (`bars.lua:566`); first throw prints once,
  all throws counted in `ST.bar_hook_errors`, site quarantined after 25.
  Rogue `on_bar_update` still must be throw-safe by construction — the guard
  is a backstop with a counter, not a license to throw.
- H3 `main.lua:791-816` `callback_event_handler` pcalls the per-event handler
  with per-event counts + one notice. Rogue CLEU (if any) inherits this.
- H5 `swing_source.lua:97-141,206/211/233/238/244/271,277,314` reject +
  speed-read-keep counters, one-time sustained-reject notice, surfaced via
  `main.lua:1662-1690` `diagnostic_text` (`/st diag`). Forever rogue work
  must read these counters, not invent its own.
- H6 `main.lua:1113-1150` all seven thin UNIT_SPELLCAST_* handlers
  early-return pre-init; callee `ST:class_on_spellcast_event`
  (`main.lua:1755`) has no init guard (verified read). Rogue
  `on_spellcast_event` must self-guard on `interfaces_are_initialised`/nil
  visuals.
- M1 `main.lua:1432-1510` bounded rf retry (3 attempts, 0.05/0.1/0.2 s
  backoff); M2 `main.lua:1447-1456` nil-checker re-arm capped at 100 laps.
- M7 `enemy_swing.lua:119-156,355,452-495,574` cycle provenance
  (`live`/`cached`/`fallback`): fallback dims + shows target name, nil clock
  hides. Rogue TTD/Rupture-vs-Eviscerate logic must check provenance — never
  time interrupts/peels to a fallback 2.0 s cycle.

fix-guides (weave/nextaction/nextaction_ui/compat-observability/paladin/shaman
+ 8 state suites, 35/0, 15/15 mutations —
`bench/fix_guides_weave_2026-10-19.md`):
- H4 `weave.lua:207,225,276` unknown cast → nil (never 0); `classes/shaman.lua:2063,1790`
  hide markers/position rows on nil. Rogue tick predictor must follow the
  same rule: ambiguous tick → nil (hidden), never a guessed tick.
- M6 `nextaction.lua:376,857/909` + `nextaction_ui.lua:530,613-624,707`:
  `inputs.inputs_unknown` threads engine→frame, frame renders "…" with a
  SetText latch; non-table gather flags unknown. Rogue provider must set the
  bit (pattern: `classes/paladin.lua:2482,2749`; frozen doc
  `classes/paladin.lua:1625-1635`).
- M3 `classes/paladin.lua:564,651-657` unmatched-payload counter + one-time
  notice (diag still pending — lane-external residual).
- M4 `classes/paladin.lua:796,802,1311-1322,1415-1427` distinct "seal data
  unknown" band (swing-unusable + seals-readable); broken-mirror case stays
  hidden by design (cite, not fix).
- M5 `compat.lua:549` `api.auras_may_be_secret()` + paladin consumer
  `classes/paladin.lua:1079-1093,1321,1338` ("lust unknown" behind the
  `twist_lust_override_enabled == true` opt-in). Rogue lust/secret handling
  must reuse this probe, not re-probe `C_Secrets`.
- R4 both gates already `== true` (`classes/paladin.lua:1101`,
  `classes/hunter.lua:1068`, pin in `tests/hunter_state.lua`); G1 Cata/Mists
  inert-standin profiles in `tests/smoke.lua`; G2 lust→0.6× band pin
  (`tests/paladin_state.lua` §17); G3+G6 lag defaults 1.4/15 + deadzone
  independence (static + behavioral); G4 combat transitions keep the mainhand
  record; G5 three weave cross-term cases.

## 1. Class-module contract checklist (what `classes/rogue.lua` must satisfy)

Convention anchors (all five classes share the shape; rogue copies it):
- [ ] Module open: `local addon_name, st = ...` + `LibStub("AceAddon-3.0"):GetAddon(addon_name)`
  + `local api = st.api` (pattern: `classes/paladin.lua:4-9`). Never call a
  cross-client API directly — `compat.lua` `st.api.*` only (`compat.lua:205-274`
  spell/cooldown/usable, `:511-549` aura scan + secret probe, `:993-1087`
  combat-log/totem/family-spell-id). Raw `GetTimePreciseSec()` must never
  leave compat — bars compare against `GetTime()`.
- [ ] Registration exists already: `ST.ROGUE = {}` (`main.lua:60`) and hands
  `ROGUE = {"mainhand","offhand","ranged"}` (`main.lua:88-92`). Generic
  `ST:get_class_table()` (`main.lua:189-191`) needs no change. No new
  `player_class ==` branch except where CLEU/event gating enumerates classes
  (§3).
- [ ] `ST.ROGUE.defaults` exists but is BAR-ONLY (`config_presets.lua:569-598`).
  Must grow class keys mirroring `ST.SHAMAN.defaults`
  (`config_presets.lua:603-655`: weave keys + `show_shaman_*` + `nextaction_*`
  OFF-default + `hud_show_*` ON-with-master-off) or `ST.WARRIOR.defaults`
  (`config_presets.lua:698-769`). Already wired: `config.lua:63`
  (`ROGUE = ST.ROGUE.defaults`). Nil-safe rule: `== false` hides, nil = off,
  defaults documented for the options pass; no default-visible change without
  an explicit gate (standing rule).
- [ ] Colors/proc keys follow the per-class pattern (warrior:
  `config_presets.lua:698-733` hs/cleave/rampage colors + `show_warrior_*`
  target-debuff bars; paladin seal colors; shaman `show_shaman_*`). Rogue
  needs: energy-tick/pooling tint colors, SnD/Rupture/EA bar colors,
  Shiv-ready glow color — all 0-255 RGB + 0-1 alpha via the shared
  convert path.
- [ ] `HUD_SLOTS` + `get_hud_state` implement the FROZEN contracts in
  `hud.lua:20-60` (descriptor: key/title/kind/spell/cooldown_spell/texture/inv_slot;
  provider: remaining/duration/start/reverse/text_remaining/desaturate/usable/
  in_range/glow, called ≤1/tick/slot at 0.05 s, may reuse one table).
  Anchored examples: `classes/paladin.lua:2797`, `classes/hunter.lua:1142`,
  `classes/druid.lua:1703` (warrior/shaman same-contract, verified by grep).
  No-HUD_SLOTS = silent no-op (do not rely on it — rogue ships slots).
- [ ] Guide provider implements the FROZEN contract in
  `nextaction_ui.lua:13-82`: `slots` (key/spell_id/cooldown_key + optional
  display fields; ≤6 slots expected for non-paladin, `:23-25`), `gather`
  (caller-owned reused table, no per-call allocation, `:27-31`), `evaluate`
  (every out field written every tick: action/hold/hold_text/filler_slot/
  judge_slot/rotation_key/waiting_judgement, `:33-46`), optional
  `rotation_key`/`rotation_names`/`labels` (`:48-55`). Anchored providers:
  `classes/paladin.lua:2671`, `classes/druid.lua:1651`; gather fns
  `classes/paladin.lua:2465`, `classes/druid.lua:1496`,
  `classes/hunter.lua:793`, `classes/warrior.lua:2167`,
  `classes/shaman.lua:2265`. Rogue adds `ST.ROGUE.guide` + `gather_guide_inputs`.
- [ ] `on_bar_update(self, hand)` per-frame hook, every class:
  `classes/paladin.lua:1231`, `classes/druid.lua:1178`,
  `classes/hunter.lua:384`, `classes/shaman.lua:1963`,
  `classes/warrior.lua:1898`. Must drive BOTH `st.nextaction_ui.on_bar_update`
  (paladin `:1261`, druid `:1202`, hunter `:423`, shaman `:1994`, warrior
  `:1922`) and `st.hud.on_bar_update` (paladin `:1268`, druid `:1211`,
  hunter `:400`, shaman `:2002`, warrior `:1930`) in that order — the guide
  frame and HUD tick from the class hook. Post-fix the call site is guarded
  (`bars.lua:681` via `run_guarded`, `bars.lua:517-556`); still no throwing,
  no per-tick allocation, lockdown-safe (frame-not-ready retry pattern, cf.
  druid `:215`, shaman `:968`, warrior `:1310` comments).
- [ ] `on_spellcast_event(self, event, unit, cast_guid, spell_id)` where the
  class consumes the spellcast lifecycle: `classes/shaman.lua:767`,
  `classes/warrior.lua:1238`. Dispatch: seven thin handlers
  `main.lua:1113-1150` (post-fix pre-init guard) → `ST:class_on_spellcast_event`
  (`main.lua:1755`, no init guard — callee must self-guard). Variants
  `on_spellcast_failed_quiet`/`on_spellcast_succeeded`
  (`classes/druid.lua:174,181`) keep their own guards. Rogue needs the
  lifecycle hook only if it consumes casts (Thistle Tea item CD, Shiv cast
  confirmation) — otherwise omit entirely (no stub).
- [ ] `on_combat_exit(self)`: `classes/paladin.lua:1549`,
  `classes/druid.lua:257`, `classes/hunter.lua:467`,
  `classes/shaman.lua:869`, `classes/warrior.lua:539`. G4 pins the contract:
  combat flips `in_combat`, the mainhand record object is preserved
  (speed/start/ends_at/is_full untouched), class hook fires once per exit.
  Rogue must not clear/duplicate the player cycle here.
- [ ] Spell-id tables: highest-rank-wins `resolve_rank`/`resolve_known`
  pattern (`classes/warrior.lua:220-265,2092-2099`;
  `classes/hunter.lua:724-762`) + Anniversary name-fallback tables for any
  CLEU matching (paladin `resolve_soc_proc_names`
  `classes/paladin.lua:566,642-657` + `twist.lua:67-88`; R1 rule). Poison/
  Shiv/Overkill/Vanish aura ids: NO ids are claimed anywhere in the rogue
  corpus (rogue_research §5.15) — tables ship empty with in-client fill, never
  with remembered ids (lessons: a remembered id is a rumor).
- [ ] Harness pins required (proctor standard): new `tests/rogue_state.lua`
  (sandbox + fake clock + captured timers, behavior outcomes not
  "runs-without-error"), `guide_contract.lua` parity extension (fake-provider,
  degenerate, gather, real-frame ticks — cf. `tests/guide_contract.lua:268+`),
  `toc_check.lua` per-flavor engine assertions, `smoke.lua` client profiles
  only if rogue adds family-specific resolution. Bite proofs on
  `/tmp/opencode` copies (guard-stripped copy must fail the new check).

## 2. Guide-engine fit: does `nextaction` cover rogue?

Short answer: the FRAME covers rogue with zero changes; the DECISION MODEL
does not — rogue needs its own pure module beside `nextaction.lua`, not a
branch inside it.

- Engine shape today (`nextaction.lua:22-38`): frozen inputs
  speed/swing_remaining/G/gcd_remaining/twist_window/reaction/cs_remaining/
  judge_remaining/seal/cs_delay_max/waiting_judgement/melee_count/mana_pct/
  creature_type/filler_remaining; out action ∈ soc/sob/twist/cs. Rotation
  selection is swing-speed thresholds (`:187-231`) and the whole model is
  twist-seal/Crusader-Strike/Judgement/filler-consecration-exorcism. None of
  rogue's core state (energy_now, energy_tick_in, combo points, SnD_remains,
  rupture_remains, envenom_buff_remains, deadly_stacks, EA_remains,
  pooling_band) exists in the frozen set, and the out vocabulary has no
  spender/builder/finisher slots.
- Fit verdict per rogue signal (rogue_deep §4 table): SS-after-swing Era cue,
  weapon-swap tint, Vanish/Overkill/MoS windows, AR+BF stacked glow, Shiv
  upkeep, poison reminder — all PRESENTATION on existing patterns
  (`on_bar_update` tint/glow, paladin CD-group, aura+cooldown reads). The two
  gaps needing new math: (a) proc-aware tick predictor (druid D5 template only;
  Combat-Potency 15-energy grants must not re-anchor the 2 s clock —
  rogue_deep §2.2); (b) the rogue decision itself (pool vs spend, Rupture vs
  Eviscerate via TTD, Envenom rules that DIFFER per client — never share one
  Envenom rule: rogue_research §3.5).
- Smallest extension shape (all opt-in, archived behavior untouched — same
  pattern as the Era/TBC/Forever opt-ins `nextaction.lua:40-79`):
  1. NEW pure `rogue_guide.lua` (sibling of `warrior_guide.lua`,
     `druid_guide.lua`, `shaman_guide.lua`, `hunter_guide.lua` — note these
     live at ROOT, not in classes/; Toc order root-guides before classes is
     load-bearing for the provider reference). Pure: pooling-band predicate
     (65-pre/85-post TBC bands as data, not constants), Rupture-vs-Eviscerate
     decider on TTD (druid D4 EMA reuse), per-client Envenom rule table.
  2. Optional frozen-input EXTENSION (missing = archived behavior): energy_now,
     energy_tick_in, cp, snd_remains, rupture_remains, envenom_buff_remains,
     deadly_stacks, ea_remains, time_to_die, lust_active. Never rename the
     frozen paladin names.
  3. Provider `ST.ROGUE.guide` mapping the pure verdict onto the frozen
     display fields + `labels = { hold = "POOL", ride = "NOW" }`-style
     overrides (`nextaction_ui.lua:53-55`; frame already selects ride vs hold
     text `:554-565`). HOLD/RIDE equivalents need NO frame change:
     out.hold + out.hold_text carry "POOL — tick in 0.3s" / "SPEND now".
  4. `inputs_unknown` set exactly like paladin (`classes/paladin.lua:2482`)
     when swing/energy/CP reads are unusable; frame renders "…" with latch
     (`nextaction_ui.lua:613-624`). Retail: engine short-circuit
     (`nextaction.lua:354-365`, family RETAIL) keeps rogue widgets inert;
     Forever runs on swing activity, never `st.is_mainline` (frame header
     `nextaction_ui.lua:10-11` — standing rule).

## 3. Sixth-class wiring list (exact files)

1. All 7 flavor TOCs + base, tail class block in load order (libs → core →
   guides → main/bars/ui → config → classes): append `classes\rogue.lua`
   AFTER `classes\warrior.lua` (dependency: needs config/st.api/frame modules
   loaded; backslash paths — case-sensitive loaders). Files/lines today:
   `SwedgeTimer.toc:66-70`, `SwedgeTimer_Vanilla.toc:66-70`,
   `SwedgeTimer_TBC.toc:66-70`, `SwedgeTimer_Wrath.toc:66-70`,
   `SwedgeTimer_Cata.toc:66-70`, `SwedgeTimer_Mists.toc:66-70`,
   `SwedgeTimer_Mainline.toc:65-69` (no LibClassicSwingTimerAPI line — keep
   it that way). `tests/toc_check.lua:120-310` pins per-flavor engine
   divergence both directions — extend the class-coverage half.
2. `config_presets.lua`: expand `ST.ROGUE.defaults` (`:569-598`, bar-only
   today) with class keys (energy-tick toggle, pooling-band data, SnD/rupture/
   EA cue toggles + colors, Shiv/Tea cues, `nextaction_*` OFF-default matching
   shaman `:630-641`/warrior `:735-746`, `hud_show_*` ON-with-master-off
   matching shaman `:643-654`/warrior `:751-769`). `config.lua:63` already
   maps ROGUE — no change there.
3. `option_tables.lua`: ADD `ST.class_opts_funcs.ROGUE` — the dispatch
   (`:701-706`) calls it by `player_class` key; five exist
   (`:1239` PALADIN, `:2595` WARRIOR, `:3086` HUNTER, `:3412` DRUID,
   `:3930` SHAMAN), ROGUE grep-confirmed absent. Mirror the SHAMAN section
   shape (`:3930-4263`: weave toggles + nextaction group + slot toggles via
   `hud_rotation_widgets`, `:804-814`) with nil-safe reads and the
   `== false` toggle discipline.
4. `classes/rogue.lua` (NEW): HUD slots `ST.ROGUE.HUD_SLOTS` +
   `get_hud_state` (contract `hud.lua:20-60`); guide `ST.ROGUE.guide` +
   `gather_guide_inputs` (contract `nextaction_ui.lua:13-82`); `on_bar_update`
   driving both consumers; `on_combat_exit`; spell-id tables (empty until
   in-client fill). Suggested slot set (from rogue_deep §3 teardown): SnD,
   Rupture, EA-duty, AR, BF, Thistle-Tea item cue, Kick/Kidney short-CD,
   trinket1/2.
5. `main.lua`: NO generic change (ST.ROGUE + hands + config mapping all
   present). Two conditional touches ONLY if rogue needs them: (a) CLEU
   registration (`:557-559` PALADIN-or-WARRIOR + non-mainline) — rogue default
   is NO CLEU (aura/power/CP reads); if Shiv-cast matching on `_TBC` is ever
   needed, extend with the R1 name-fallback, never a bare id table. (b) No new
   `player_class == "DRUID"`-style branches (`:242,431,952,1267,1283`) unless
   a rogue-specific bar behavior is proven in-client.
6. HUD: nothing in `hud.lua` itself (generic renderer `hud.lua:423-429` reads
   whatever descriptors exist). Add `hud_show_<key>` defaults (see #2) +
   options text (see #3).
7. Practice: `H.register_scenario` (`practice.lua:1509-1543`) — add
   `class = "ROGUE"` scenarios beside PALADIN (`:1800,1971`), HUNTER
   (`:2095`), WARRIOR (`:2216`), DRUID (`:2365`), SHAMAN (`:2456`). Candidates:
   energy-pooling drill (cast-start fraction vs tick marker; grade bands reuse
   `H.WEAVE_MARGIN_BANDS`, `:2404-2410`), Era SS-after-swing drill (post-MH
   0.1–0.2 s window; rogue_deep §2.1). `practice.lua:2436-2438` already treats
   nil markers as unscored — rogue nil-tick composes for free.
8. Root pure module `rogue_guide.lua` + TOC line beside the other
   `*_guide.lua` entries (base toc `:44-47`: nextaction, warrior_guide,
   druid_guide, shaman_guide, hunter_guide — add rogue_guide in that group,
   BEFORE `practice.lua:50`/`main.lua:52` which consume it).
9. Tests: NEW `tests/rogue_state.lua` (+ harness registration in
   `tests/run.sh` — count moves 35→36, update the `desks/journal.md` baseline
   claim when the orchestrator accepts it), guide-parity cases in
   `tests/guide_contract.lua`, TOC pins in `tests/toc_check.lua`.

## 4. Post-fix integration: what changed in §§1–3, and constraining residuals

Changed by the fix lanes (nothing in §§1–3 above describes the pre-fix tree):
- Bar engine state: H1 nil-shape + `engine_dead` render — §1 hook checklist
  and §2 swing-gating assume this; pre-fix text describing a "1 s stub" is
  stale.
- Hook/dispatch hardening: H2/H3 — §1 cites the guarded call sites
  (`bars.lua:517-556,681`; `main.lua:791-816`).
- Forever observability: H5 counters via `/st diag` — §3 Forever work reads
  them, doesn't re-emit.
- Spellcast guard shape: H6 — §1 states the callee-self-guard rule.
- Weave/guide contracts: H4 nil-cast, M6 `inputs_unknown`, M5 secret probe,
  M3 counter, M4 band — §2 extension shape threads all three.
- Family matrix: G1 Cata/Mists inert-standin proven — rogue inherits it; no
  Cata/Mists swing behavior may be assumed.

Unresolved hunter/proctor residuals that CONSTRAIN rogue design (build
prerequisites, not optional):
- CLEU R1 (Anniversary names-not-ids): any rogue CLEU matching on `_TBC`
  (Shiv cast, poison procs, Vanish/Overkill windows) MUST ship id tables +
  localized-name fallback tables with retry (pattern
  `classes/paladin.lua:623-657`, `twist.lua:67-88`; M3 counter pattern for
  sustained-zero observability). Until then: aura/power/CP reads only on
  `_TBC`. (hunter M3 UNCONFIRMED half; proctor leaves `/dump` slot-type
  in-client per TESTING.)
- Secret-regime M5: under Midnight secrecy, lust/haste/cooldown reads degrade
  to unknown (compat E2 whole-or-nothing `compat.lua:440-485`, M5 probe
  `:549`). Rogue AR+BF stacked-glow, pooling bands, and any lust-gated cue
  must render the unknown state (paladin `twist_lust_unknown` pattern) — never
  confident un-hasted advice through a lust. `/st diag` `secrets` line is the
  only backstop today (diag lane-external).
- Unknown-input M6: provider sets `inputs_unknown` whenever swing/energy/CP
  cannot be trusted; frame shows "…" (no advice beats wrong advice — the
  shaman/paladin `nextaction_enabled=false` default precedent,
  `config_presets.lua:630-641`). All-defaults input sets are indistinguishable
  from legitimate ones inside the engine (`nextaction.lua:34-38`) — the
  PROVIDER owns the bit.
- H4 corollary for the tick predictor: Combat-Potency 15-energy grants and
  gear-proc energy must not re-anchor the 2 s tick clock (Yam-corrector
  requirement, rogue_deep §2.2); failed disambiguation → nil tick (hidden),
  never a guessed spark.
- M7 corollary: `enemy_swing` fallback cycles are display fiction — rogue
  Rupture-vs-Eviscerate TTD must consume only `live` provenance or its own
  health-velocity tracker (druid D4 EMA reuse), never the 2.0 s fallback.
- M6-Retail boundary: Retail rogue = widgets only (CP/energy/poison/buff
  reads where cheap via UnitAura); no swing features — stand-in never swings
  so swing-activity gating hides them automatically.

## 5. Sequenced build plan (4 disjoint slices)

Slice A — module skeleton + wiring (no behavior).
- Scope: NEW `classes/rogue.lua` (open pattern, empty id tables, `HUD_SLOTS`
  + `get_hud_state` stubs returning nil-state, `guide` provider returning
  `inputs_unknown=true`, `on_bar_update` driving both consumers with
  lockdown-safe frame retry, `on_combat_exit`); `ST.ROGUE.defaults` class keys
  (OFF-defaults per standing rule); 8 TOC appends; `ST.class_opts_funcs.ROGUE`
  section; `tests/rogue_state.lua` + toc pins.
- Pins: load-order (all 7 TOCs list it post-config), defaults shape
  (nil-safe reads), HUD silent-until-enabled, guide "…" until inputs exist,
  combat-exit record preservation (G4 mirror).
- Validation: `bash tests/run.sh` (35→36 steps, 0 failed) + luacheck floor
  (2/0) + mutation proofs on `/tmp/opencode` copies + `tests/toc_check.lua`.

Slice B — energy tick + Era swing cue (presentation, no decisions).
- Scope: proc-aware 2 s tick predictor (Yam rule: CP-15 ≠ re-anchor),
  energy-tick spark + 65/85 pooling tint (TBC data-driven), Era-only
  post-MH-swing 0.1–0.2 s SS window (family-gated `_Vanilla` + sword-relevant
  loadout; NEVER on `_TBC`+ — Sno deliberately removed it), weapon-swap tint
  with GCD+reset cost in copy, MH/OH poison reminder (+ charges on Forever —
  probe shape UNCONFIRMED, in-client check).
- Pins: predictor re-anchor cases (CP grant vs true tick), Era gate both
  directions, nil-tick hides (H4 rule), swap copy carries cost.
- Validation: `tests/rogue_state.lua` tick/predictor cases + `bars_state`
  spark/tint cases; in-client: tick accuracy vs Yam overlay, Era SS-window
  feel (`TESTING.md` swing section).

Slice C — decision provider (pure + wiring).
- Scope: NEW root `rogue_guide.lua` (pool-vs-spend, Rupture-vs-Eviscerate on
  TTD, per-client Envenom table, EA-duty refresh, Shiv upkeep, Thistle-Tea
  deficit cue); `ST.ROGUE.guide` + `gather_guide_inputs` (frozen display
  fields + `inputs_unknown` ownership); labels POOL/NOW; `hud_show_*` slots
  live (SnD/Rupture/EA/AR/BF/Tea/Kick/trinkets).
- Pins: pure-matrix cases per client (Era combat, TBC Imp-EA, WotLK sin
  let-expire-unless-capping, retail chain — each with its own Envenom rule),
  TTD-boundary decider cases, unknown-input "…" cases, lust-unknown latch
  (M5 pattern) cases.
- Validation: `tests/rogue_state.lua` + `guide_contract.lua` parity
  (gather→evaluate→frame, degenerate inputs, latch); NO engine change —
  `nextaction.lua` untouched.

Slice D — practice + target polish + residual closure.
- Scope: two `practice.lua` scenarios (energy-pooling drill, Era SS-timing
  drill); TTD EMA wiring (druid D4 reuse); TTD-vs-fallback guard (M7
  provenance check); `/st diag` lines for M3-counter/M5-regime IF the
  orchestrator opens diag.lua (out of slice scope otherwise — session state +
  visible affordance already ship); options copy for
  `weave_range`-style hide-on-unknown discoverability.
- Pins: scenario grade bands (S/A/B/C/D + F-clip mirror), TTD EMA cases,
  fallback-provenance refusal cases.
- Validation: full harness + mutation battery; owner in-client TESTING pass
  (tick, SS window, SnD/Rupture upkeep, EA juggle, Vanish/Overkill window).

## Tooling log

Code Mode only (no web needed — pointer lane, no new sourcing): `read`/`grep`
in-tree for every anchor above; `shell` for TOC tails + options dispatch +
`hud.lua:20-60` + `main.lua` class-branch enumeration; `desks/` read for both
fix-lane journals. No addon edits; no test runs (validation owner:
orchestrator — checklist + minimal extension shapes + disjoint slices above).
