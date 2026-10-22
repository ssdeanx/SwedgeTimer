# Hunter rotation vs wowsims sims — audit 2026-10-19

Scope (read-only): `classes/hunter.lua`, `hunter_guide.lua`, `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`.
Method: offline read of our files + webfetch of wowsims sim sources (raw GitHub + API listings). No addon edits, no git. Sim facts below are SIM-CONFIRMED (source said it); CLIENT-UNCONFIRMED means still needs in-client `GetSpellInfo`/probe check. Our citations are `file:line` on the current tree.

## Sim sources actually read (no invented urls)

- SoD repo: https://github.com/wowsims/sod
  - `sim/hunter/chimera_shot.go` (409433, 6s CD, Serpent-gated proc + rollover)
  - `sim/hunter/runes.go` (Lone Wolf, Sniper Training 415399, Lock and Load 415413, trapRange 35/5, Viper 415423)
  - `ui/hunter/apls/p7_weave.apl.json` (P7 weave: Chimera > LnL-gated Arcane/Multi > movement/melee-weave tech)
  - `ui/hunter/apls/p3_ranged_mm.apl.json` (Serpent upkeep 13554, Rapid Fire 3045, Chimera 409433 gating)
  - `sim/hunter/dps_hunter/dps_hunter_test.go` (phase/talent/gear matrix)
- Era repo: https://github.com/wowsims/classic
  - `sim/hunter/hunter.go` (Era kit: Aimed/Arcane/Multi/Raptor/Mongoose/WingClip/traps/Volley/Serpent; Auto windup 500ms, haste-scaled)
- TBC repo: https://github.com/wowsims/tbc-new
  - `sim/hunter/steady_shot.go` (rank **34120**, 1500ms)
  - `sim/hunter/multi_shot.go` (rank **27021**, 500ms)
  - `sim/hunter/hunter_test.go` (weave vs turret rotations, Melee weave variable)
  - `ui/specs/hunter/dps/apls/default.apl.json` (Kill Command 34026 first; Mana group Viper 34074 / Hawk 27044; Multi+Arcane gated on `Next cycle gap after steady`; Weave move group)
- Wrath repo: https://github.com/wowsims/wotlk
  - `sim/hunter/chimera_shot.go` (53209, 10s CD, Serpent-proc 53353 / Scorpid refresh)
  - `sim/hunter/explosive_shot.go` (**60053** R4 / **60052** R3 downrank pair, 6s CD, LnL engine)
  - `sim/hunter/steady_shot.go` (**49052**, 2s base hasted, Improved Steady Shot aura 53220)
  - `sim/hunter/talents.go` (Lock and Load 56344 22s ICD; Readiness 23989 full reset + smart delay; Sniper Training 53304; Piercing Shots 53238)
  - `ui/hunter/presets.ts` (Simple rotation: Serpent sting + trapWeave + `allowExplosiveShotDownrank`; DefaultOptions `timeToTrapWeaveMs: 2000`)
- Forever repo: https://github.com/wowsims/forever
  - `sim/hunter/hunter_test.go` (default APL + turret variant; `TestSniperShotExtendsAutoShotRange`; `TestEachHunterKeepsOneStingPerTarget`; hawk/pet suites)
  - `sim/hunter/sniper_shot.go` (talent-gated; buff extends Auto range)
  - `sim/hunter/summon_hawk.go` (count from spell EffectN(3); 18s `hawkSummon`; round-robin replacement)
  - `sim/hunter/spell_data_auto_gen.go` (**SniperShot Ranked(1310687, 1310785, 1310786)**; **SummonHawk Ranked(1293241, 1293525, 1293526, 1293527)**, triggered 1293248/1312639)
  - `ui/specs/hunter/dps/apls/default.apl.json` (HHA sequence: 2x Hawk 1293527 + Arcane 14287; Multi 2643 + Aimed 20904 weave guards; Melee weave default true; Serpent 25295 upkeep)
- `wowsims.github.io`: attempted via API, rate-limited (403) — no sim rotation code located there. UNCONFIRMED, no url cited.

Our engine reference: `hunter_guide.lua:196-296` (frozen rule matrix), `hunter_guide.lua:521-696` (evaluate), `classes/hunter.lua:970-1268` (gather), `classes/hunter.lua:798-847` (slots).

---

## ERA (Vanilla / Classic Era 1.15.x — sim: wowsims/classic)

MATCH
- Aimed 3s-cast weave above Multi weave, both clip-gated, Raptor as melee surface — our rules 6a/6b/7 (`hunter_guide.lua:259-296`) + Era slot set (`hunter_guide.lua:27-33`) match the Era kit direction (Aimed/Multi/Raptor in `sim/hunter/hunter.go` Initialize).
- Steady never prompts on Era (no Steady in Era sim; our `steady_known` gate `hunter_guide.lua:270-275`, `classes/hunter.lua:1117-1119`). Correct silence.

GAP — Serpent Sting / Arcane / traps / Volley / Mongoose / Wing Clip never prompted (impact: MEDIUM)
- Sim registers all of them (`sim/hunter/hunter.go` Initialize: Serpent, Arcane+Aimed share timer, Multi timer, Raptor, Mongoose, Wing Clip, Volley, all three traps). Our Era set is aimed/raptor/multi only (`hunter_guide.lua:27-33`, slots `classes/hunter.lua:841`). Top-parse Era hunters keep Serpent up and trap-weave; guide is silent on all of it.

GAP — melee-weave movement tech (impact: LOW-MEDIUM)
- Sim enables `AutoSwingMelee` and models Raptor/Mongoose in the melee window. Our rule 7 only RIDE-surfaces an already-queued Raptor (`hunter_guide.lua:294-295`); no Mongoose/Wing prompt, no move cue.

CONFLICT — none on the weave itself. Our inclusive window HOLD (`hunter_guide.lua:226-231`) is conservative vs the sim's no-clip modeling; direction agrees.

## SOD (Season of Discovery — sim: wowsims/sod)

MATCH
- Chimera 409433 instant 6s CD top of the ranged weave (`sim/hunter/chimera_shot.go`; our rule 5b `hunter_guide.lua:322-325`, slot `hunter_guide.lua:52-58`, gather `classes/hunter.lua:1188-1189`).
- Aimed/Multi below Chimera, Steady silent on SoD family (our `steady_known=false` path; SoD sim has no Steady Shot spell).
- Pet-rune build reading as plain Era (`hunter_guide.lua:60-61`, `classes/hunter.lua:951-958`) matches the sim treating pet builds as separate APLs.

GAP — Serpent Sting upkeep (impact: HIGH)
- Sim APLs explicitly maintain Serpent (`p3_ranged_mm`: `not dotIsActive 13554 → cast`; `p7_weave`: `dotRemainingTime 25295 ≤5s → Chimera`). SoD Chimera only pays (bonus + rollover) with Serpent up (`sim/hunter/chimera_shot.go` ApplyEffects). Our engine never prompts Serpent (deferred, `hunter_guide.lua:49-51`) — guide can prompt a naked Chimera.

GAP — Lock and Load 415413 (impact: MEDIUM-HIGH)
- `p7_weave.apl.json` gates Arcane/Multi/Aimed lines behind `auraIsActive 415413`. `runes.go applyLockAndLoad` (trap → 20s aura, free shots + CD reset). Our engine has no LnL input at all.

GAP — traps + Sniper Training + mana (impact: MEDIUM)
- Trap Launcher range 35 vs 5 (`runes.go trapRange`), Sniper Training stacks 415399, Viper cancel 415423 at ≥95% / potion at <55% (`p7_weave`). Our SoD set has no trap/sting/mana inputs (HUD mana tint only).

GAP — melee-weave movement cues (impact: LOW)
- Sim moves 12yd↔5yd on `autoTimeToNext Melee/Ranged + gcdTimeToReady` (`p7_weave` move actions). Our guide only HOLD/RIDE, no move cue. Not a rotation error, note as kit gap.

CONFLICT — none on Chimera priority.

## TBC (Anniversary 2.5.6 — sim: wowsims/tbc-new)

MATCH
- Kill Command 34026 #1 BM priority (`default.apl.json` priorityList position 1; our rule 3 `hunter_guide.lua:312-314`, ids `classes/hunter.lua:59-61`).
- Steady 1.5s filler under clip guard (`steady_shot.go` 1500ms; our rule 6c `hunter_guide.lua:270-275`); Multi 0.5s weave (`multi_shot.go` 500ms; our rule 6b).
- Bestial Wrath 19574 / Rapid Fire 3045 as on-CD pops (our rules 4/5 `hunter_guide.lua:315-320`).

GAP — Arcane Shot 27019 never prompted on TBC (impact: HIGH)
- Sim APL has a dedicated `Use Arcane Shot` variable and multiple Arcane-gated entries (`default.apl.json`). Our TBC matrix has no Arcane slot/input — Arcane exists only on the Wrath set (`hunter_guide.lua:43-45`, `classes/hunter.lua:1194-1195`). Sim-optimal TBC filler mixes Arcane; guide never shows it.

GAP — mana: Viper 34074 / Hawk 27044 / potions (impact: LOW-MEDIUM)
- Sim `Mana management` group (Viper <5%, Hawk ≥25%, Mana Pot). Our gather has no mana input; guide keeps prompting Steady into OOM.

GAP — melee weave is sim-default (impact: MEDIUM)
- Sim default `Melee weave=true` with Wait-at-melee 400ms, Buffer `min(0.5s, 25% swing)`, `Next cycle gap after steady` gating (`default.apl.json` valueVariables). Our engine has no weave/move/wait cues; Raptor is a passive surface only. Top-parse TBC is weave; guide teaches turret.

GAP — prepull/opener (impact: LOW)
- Hawk 27044 at -20s, no other prepull in sim APL beyond that + Steady at 0.5s. Our guide has no prepull/mark surface. One-time, note only.

CONFLICT — Steady rank: sim casts rank **34120** (downrank for mana, `steady_shot.go BySpellID(34120)`); we resolve to the highest known rank (`classes/hunter.lua:853-856`). Guide icon/label follows max rank while sim-optimal may be rank 1. Severity LOW, needs 2.5.6 mana-math confirmation — do not change ids on this audit alone.

NOTE — buffer shape: sim Buffer is swing-adaptive (`min(0.5s, 25% swing)`); ours is fixed grace 0.5/0 + latency (`hunter_guide.lua:343-477`). Direction agrees (conservative); constants differ. No action, recorded.

## WRATH (WotLK 3.80.2 — sim: wowsims/wotlk)

MATCH
- Six-arm priority Kill Shot (≤20%) > Chimera (MM) > Explosive (SV) > Aimed (instant) > Arcane (non-SV) > Steady filler (our W1–W6 `hunter_guide.lua:203-225`) matches the sim spell kit (Chimera 53209 10s; Explosive 6s; Steady 49052 filler; research `docs/research/rotations_wrath.md:5-38` provisions it).
- No window hold / no clip check on Wrath (Auto fires during casts; our `is_wrath` bypass `hunter_guide.lua:607-611`). Correct.
- SV Arcane suppression (shared CD with Explosive; our `explosive_known ~= true` arm `hunter_guide.lua:597-601`). Correct.
- ArP-cap Arcane drop documented as owner-skips (`hunter_guide.lua:220-221`) — sim-consistent (no prompt needed).

GAP — Lock and Load (impact: HIGH, SV-defining)
- Sim: 56344, 22s ICD, 2 stacks, free Explosive/Arcane + CD reset on Black Arrow/Trap ticks (`talents.go applyLockAndLoad`). Our Wrath inputs have no LnL aura/stack input; engine cannot distinguish a free instant from a full-cost one.

GAP — Explosive downrank pair R4 60053 / R3 60052 (impact: MEDIUM-HIGH)
- Sim models both ranks + `allowExplosiveShotDownrank` (`presets.ts`) for the LnL R4→R3→R4 sequence (research `rotations_wrath.md:34`). Our `explosive_shot_ids = {53301}` (`classes/hunter.lua:92-96`) names the base id only. Cooldown/read may follow the wrong rank id in-client. Rank coverage incomplete — needs 3.80.2 spell-cache confirmation, no id change in this audit.

GAP — Serpent Sting upkeep (impact: HIGH for MM)
- Sim Simple rotation forces Serpent sting + `multiDotSerpentSting`; Chimera consumes/rolls it (`chimera_shot.go`: Serpent rollover + 53353 proc, else Scorpid refresh). Our Wrath set has no sting slot/input (deferred `hunter_guide.lua:49-51`). Chimera without Sting loses the proc nuke.

GAP — Black Arrow / trap tier + trap-weave timing (impact: MEDIUM-HIGH on SV)
- Sim `trapWeave: true` + `timeToTrapWeaveMs: 2000` (`presets.ts`); six slots are already full so traps have nowhere to go. Engine never prompts the LnL source itself.

GAP — Readiness 23989 as rotation event (impact: MEDIUM)
- Sim resets RF/Multi/Arcane/KillShot/Raptor/ExplosiveTrap/KC/Aimed/Silencing/Chimera/BlackArrow with smart RF-almost-ready delay (`talents.go registerReadinessCD`). Our Readiness only re-arms the RF bar scan (`classes/hunter.lua:300-309`); guide models no double-cooldown window.

GAP — Improved Steady Shot 53220 (impact: MEDIUM, MM)
- Sim aura: Steady crits → +15% damage/−20% cost on Arcane/Aimed/Chimera until consumed (`steady_shot.go`). Our filler has no proc/counter input; Steady x3/x4 counting is implicit in cooldown gaps (`hunter_guide.lua:224-225`) but ISS windows are invisible.

GAP — Sniper Training stationary buff (impact: LOW)
- Sim `applySniperTraining` (53304, uptime-gated +dmg while stationary). Our Wrath inputs have no stationary/movement input. Positioning aid, not rotation.

No-prompt-needed passives (recorded, no gap): Piercing Shots bleed roll 53238, Wild Quiver, Cobra Strikes, Go for the Throat — sim-modeled DPS with no rotation decision attached.

## FOREVER (WoW Forever 1.60.x — sim: wowsims/forever)

MATCH
- Sniper as 4s MM-cast under steady grace, clip-gated (our F2 `hunter_guide.lua:251-257`, `sniper_is_clip_safe` `hunter_guide.lua:481-517`) matches the sim's talent-gated Sniper Shot (`sniper_shot.go`).
- Hawk upkeep cap 2 (`HAWK_MAX_ACTIVE = 2`, `hunter_guide.lua:354`; rule F1 `hunter_guide.lua:242-250`) matches sim `newHawks` count-from-spell + 18s `hawkSummon` (`summon_hawk.go`).
- Conservative window hold kept on Forever (`hunter_guide.lua:304-308`) matches the beta "Auto Shot no longer clipped" note being sim-unconfirmed (`docs/research/forever_beta.md:14`).

GAP — CONFIRMED sim ids, our tables empty (impact: HIGH — both signature prompts silent by construction)
- Sim: SniperShot Ranked(**1310687, 1310785, 1310786**), SummonHawk Ranked(**1293241, 1293525, 1293526, 1293527**), triggered 1293248/1312639 (`spell_data_auto_gen.go`). Ours: both tables deliberately empty (`classes/hunter.lua:137-146`), documented UNCONFIRMED. Status after this audit: SIM-CONFIRMED, CLIENT-UNCONFIRMED (still needs in-client `GetSpellInfo` before wiring — no id change here).

GAP — hawk count source (impact: HIGH, blocks F1 even after ids)
- Sim derives count from spell EffectN(3) + round-robin replacement (`summon_hawk.go`). Our `hawk_active_count` is always nil (`classes/hunter.lua:1221`), F1 dormant-safe by construction (`hunter_guide.lua:250`). No client source (aura/pet-frame/other) confirmed.

CONFLICT/GAP — Multi-Shot omitted on Forever (impact: MEDIUM)
- Sim default APL prompts Multi 2643, Arcane 14287 and Aimed 20904 with time-to-weave guards (`default.apl.json`); `Use Multi-Shot=true`. Our Forever set deliberately omits Multi (`hunter_guide.lua:75-76`, deferred as sim-unconfirmed). Sim's live default disagrees — needs Forever-client confirmation, recorded as the sharpest Forever conflict.

GAP — HHA hawkweave sequence (impact: MEDIUM, BM)
- Sim HHA: 2x Hawk 1293527 + Arcane 14287 sharing a cooldown (`default.apl.json` sequence; `hunter_test.go` turret_hawk). Our engine prompts hawk/sniper independently, no sequence state.

CONFLICT — Sniper range tech vs rule 2b (impact: LOW-MEDIUM, narrow band)
- Sim proves Sniper buff extends Auto range past 41yd Hawk Eye for 3 shots (`hunter_test.go TestSniperShotExtendsAutoShotRange`). Our rule 2b HOLDs on `target_in_range == 0` (`hunter_guide.lua:570-577`) with no Sniper-buff input — at 42–45yd with the buff live we HOLD where the sim fires. Narrow band, real conflict.

GAP — Serpent/Mark/Aspects/traps kit (impact: LOW-MEDIUM each)
- Sim APL: Serpent 25295 upkeep, Hunter's Mark 14325, Aspect of the Hawk 25296 prepull, melee kit (Mongoose 14271 / Strider Kick 1317257 / Raptor 14305 / Wing Clip 14268), one-sting-per-hunter rules. Our Forever set (hawk/sniper/steady/raptor) is silent on all of it.

## RETAIL (12.x)

MATCH — inert by design. `st.family == "RETAIL"` short-circuits evaluate (`hunter_guide.lua:527-540`); the stand-in reports no ranged cycle so rules 2/6 stay silent on their own. No sim rotation applies. No gaps.

## Cross-client notes

- H2 lust suppression (rules 6a/6b off under Bloodlust, Steady spam — `hunter_guide.lua:277-283`, gather `classes/hunter.lua:1233-1261`) is ADDON-ORIGINAL: no APL lust-branch was found in the TBC/SoD/Forever APLs read. If sims keep Aimed/Multi DPS-positive under lust, H2 over-suppresses. Mark UNCONFIRMED vs sims — needs a sim query (haste-stacked Auto cycle vs cast time), no change here.
- Clip-math direction MATCHES sim APL guards everywhere (cast time + move/buffer vs time-to-next-auto). Only the constants differ (fixed grace vs adaptive buffer). No action.
- Steady-rank note (TBC 34120 downrank) and Explosive-rank note (Wrath 60053/60052 vs our 53301) are the two id-coverage risks. Neither is changed by this audit.
  **CORRECTED 2026-10-20** (desk `corpus-corrections`): both risks are now **resolved at the rotation-table level** — the TBC rotation row's **56641 does not exist on the TBC client** (the TBC APL casts 34120) and the **Forever client has no Steady Shot at all** (its row was removed); the WotLK rows' APL ids are **61006** (Kill Shot) and **60053/60052** (Explosive Shot). The hunter APL build lane re-cut the rows; the *rank-resolution policy* this audit records (resolve the highest known rank vs the sim's downrank) is unchanged. Evidence: `bench/hunter_apl_utility_build_2026-10-20.md` §3, `bench/hunter_utility_live_2026-10-20.md` §1; `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **H1**–**H4**.

## Ranked findings (new vs our tree)

1. (HIGH, Wrath SV) Lock and Load input missing — entire SV pivot invisible. Needs aura+stacks input + engine arm.
2. (HIGH, Wrath MM/SV) Serpent Sting upkeep missing — Chimera/Explosive-trapline floats without its source. Needs sting input (+ slot pressure: Wrath set is full).
3. (HIGH, Forever) Sim-confirmed ids exist (Sniper 1310687/1310785/1310786; Hawk 1293241/1293525/1293526/1293527) + hawk-count source still unknown. Wire only after in-client confirmation.
4. (HIGH, TBC) Arcane Shot 27019 never prompted — sim APL core filler. Needs slot/input (base set is full at 6/6).
5. (HIGH, SoD) Serpent upkeep missing — naked Chimera prompts.
6. (MEDIUM, TBC) Melee weave is sim-default; guide teaches turret only.
7. (MEDIUM, Wrath) Readiness/ISS/trap-weave windows invisible.
8. (MEDIUM, Forever) HHA sequence + Multi/Aimed filler absent; Sniper-range HOLD conflict at 42–45yd.
9. (LOW-MEDIUM) Mana/Viper, prepull/mark/aspect openers, Sniper Training stationary — across clients.

Validation owner: orchestrator. In-client confirmations owed: Wrath Explosive/Aimed rank ids on 3.80.2; Forever Sniper/Hawk ids + hawk-count source on 1.60.x; TBC Steady-rank optimality on 2.5.6; H2 lust-suppression sim query.
