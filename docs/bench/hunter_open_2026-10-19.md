# Hunter open items — verdicts 2026-10-19

Scope (read-only): `classes/hunter.lua`, `hunter_guide.lua`,
`bench/hunter_rotation_audit_2026-10-19.md`, `bench/competitor_gaps_2026-10-19.md`,
wowsims sim sources (fresh-fetched this session, URLs below).
No addon files changed, no git. SIM-CONFIRMED = the sim source says it;
CLIENT-UNCONFIRMED = still needs in-client `GetSpellInfo`/probe check.
Validation owner: orchestrator.

## 0. Sources actually read this session (no invented urls)

- Wrath talents: https://raw.githubusercontent.com/wowsims/wotlk/master/sim/hunter/talents.go
  (LnL 56344 22s ICD 2 stacks; Readiness 23989 + RF-almost-ready 10s hold; Sniper Training 53304)
- Wrath Steady: https://raw.githubusercontent.com/wowsims/wotlk/master/sim/hunter/steady_shot.go
  (ISS aura 53220, 12s, +15% dmg/−20% cost on Arcane/Aimed/Chimera, consumed on cast; Steady 49052)
- TBC APL: https://raw.githubusercontent.com/wowsims/tbc-new/master/ui/specs/hunter/dps/apls/default.apl.json
  (KC 34026 first; Steady 34120; Multi 27021; Arcane 27019; Viper 34074 <5% / Hawk 27044 ≥25% / pot item 22832;
  Hawk 27044 prepull −20s; Melee weave=true; NO lust branch)
- SoD runes: https://raw.githubusercontent.com/wowsims/sod/master/sim/hunter/runes.go
  (LnL 415413 trap→20s window free+refund; Sniper Training 415399; trap range 35/5; Viper 415423)
- SoD p7 weave APL: https://raw.githubusercontent.com/wowsims/sod/master/ui/hunter/apls/p7_weave.apl.json
  (potion <55%; cancel Viper 415423 ≥50%; cast Viper <5%; Chimera 409433 on Serpent 25295 ≤5s;
  prepull Falcon 469145 / Aimed 20904 / Blood Fury 20572 / Hawk 25295; move 12yd↔5yd tech; NO lust branch)
- Forever hawk: https://raw.githubusercontent.com/wowsims/forever/master/sim/hunter/summon_hawk.go
  (count = EffectN(3) base value; 18s `hawkSummon` ByID(1293248); round-robin replacement)
- Forever spell data: https://raw.githubusercontent.com/wowsims/forever/master/sim/hunter/spell_data_auto_gen.go
  (SniperShot 1310687/1310785/1310786; SummonHawk 1293241/1293525/1293526/1293527;
  Triggered 1293248/1312639; Arcane …14287; Serpent …25295; Mark …14325; Hawk …25296; Raptor …14266)
- Forever APL: https://raw.githubusercontent.com/wowsims/forever/master/ui/specs/hunter/dps/apls/default.apl.json
  (prepull Mark 14325 −22s + Hawk 25296 −20s; HHA sequence 2x Hawk 1293527 + Arcane 14287;
  Multi 2643 + Aimed 20904 weave guards; Use Aimed=false / Use Hawk=false defaults; NO lust branch)

Our side: `hunter_guide.lua:196-218` (frozen inputs incl. `lnl_ready`/`serpent_*`/`sniper_range_buff_active`
all gather-nil), `:637-648` (W-LnL), `:688-705` (5b/SoD-LnL), `:722-728` (5c dormant),
`:706-721` (F1/F2), `:729-743` (6a/6b/6c + H2); `classes/hunter.lua:125-146` (empty Forever tables),
`:300-309` (Readiness → RF rescan only), `:1220-1231` (hawk/sniper gather), `:1233-1272` (H2 + nil inputs),
`:1421-1425` (HUD mana tint).

---

## 1. Trap / ISS / Readiness display shape → BUILD AS BADGES, NOT GUIDE ARMS

What sims do:
- Readiness 23989 resets RF/Multi/Arcane/KillShot/Raptor/ExplosiveTrap/KC/Aimed/Silencing/Chimera/BlackArrow
  AND holds when RF is <10s from ready (smart double-RF delay) — talents.go `registerReadinessCD`
  SIM-CONFIRMED. A cooldown-reset event with a timing decision, not a shot priority.
- ISS 53220 is a passive 12s multiplier (+15% dmg, −20% cost on Arcane/Aimed/Chimera, consumed on cast)
  — steady_shot.go SIM-CONFIRMED. No rotation decision attached: the APL never branches on it.
- Trap-weave is APL-level timing (`trapWeave: true` + `timeToTrapWeaveMs: 2000`, presets.ts per audit §Wrath);
  the sim LnL trigger is Black Arrow / Explosive Trap ticks — talents.go SIM-CONFIRMED.

What we have: Readiness only forces the RF bar's next scan (`classes/hunter.lua:300-309`);
no double-window model, no ISS input, no trap slot (Wrath set full 6/6).

Verdict — build shape (all HUD/badge layer, zero engine arms):
- Readiness → RF-bar "2x window" badge + cooldown-reset flash in `hunter_ui`/HUD after 23989 fires
  (SST 3.1.0 reseal-marker precedent, `bench/competitor_gaps_2026-10-19.md` §P1; marker math is pure).
- ISS → proc badge/tint on Steady/Arcane HUD slots via a compat player-aura probe for 53220
  (compat follow-up; engine must NOT gate prompts on it — sims never branch on it).
- Traps/trap-weave timing → CUT from guide scope. The stateless engine cannot express APL move/wait
  timing and no slot exists (6/6 full). Park under the melee-weave/move-cue follow-up.

## 2. Mana / Viper / prepull rules → CUT FROM GUIDE; BADGE + PRACTICE SHAPE

What sims do:
- TBC APL "Mana management" group: Viper 34074 when mana <5%, back to Hawk 27044 at ≥25%,
  mana pot (item 22832) at <Viper-start+5% — fetched default.apl.json SIM-CONFIRMED.
- SoD p7: potion <55%, cancel Viper 415423 at ≥50%, cast Viper at <5% — fetched p7_weave.apl.json
  SIM-CONFIRMED. Note TBC Viper 34074 vs SoD Viper 415423 (Aspect of the Viper) differ per client.
- Prepulls are one-shot APL `prepullActions`: TBC Hawk 27044 −20s; Forever Mark 14325 −22s +
  Hawk 25296 −20s; SoD Falcon/Aimed/Blood-Fury/Hawk spread — all three APLs SIM-CONFIRMED.

What we have: HUD mana tint only (`hud_no_mana` → `usable=false`, `classes/hunter.lua:1421-1425`,
gated by `hud_mana_tint`); zero mana inputs in gather; zero prepull/mark/aspect surface.

Verdict — CUT from the guide engine. Viper is a sticky aura toggle with hysteresis (5%/25%),
wrong shape for a first-match-wins per-tick prompt engine; prepulls are one-time and the addon
has no pull-timer input (NAG pull-timer UNCONFIRMED/out-of-scope per competitor audit §P2).
Build shape instead: HUD "OOM → Viper" badge (mana% probe via compat; needs per-client Viper id)
+ prepull checklist in the practice/report layer (HST post-fight precedent, competitor audit §H2).
No engine arm, no slot.

## 3. Hawk-count sourcing → CUT UNTIL IN-CLIENT PROBE ANSWERS (single blocker)

What sims do: count comes from spell data EffectN(3) base value, 18s duration, round-robin
replacement of the oldest hawk — fetched summon_hawk.go SIM-CONFIRMED. Sims never observe hawks;
they construct them.

What we have: `hawk_active_count` always nil (`classes/hunter.lua:1221`), F1 dormant-safe by
construction (`hunter_guide.lua:706-714`). Plug-in point declared, never a live prompt.

Verdict — CUT all engine work; the blocker is observational, not computational. Candidate
in-client sources (all UNCONFIRMED, do not wire): guardian-pet enumeration (hawks are IsGuardian
dynamic pets — no unit-token contract known), triggered aura 1293248/1312639 via UnitAura scan,
combat-log summon events. When a compat probe returns a count, the existing F1 arm lights up
with no engine change. Ids alone are insufficient — count source is the gating item.

## 4. Forever ids → SIM-CONFIRMED, STILL CLIENT-UNCONFIRMED; WIRE ONLY AFTER 1.60.x CHECK

Sim ids (fetched spell_data_auto_gen.go, SIM-CONFIRMED):
SniperShot Ranked(1310687, 1310785, 1310786); SummonHawk Ranked(1293241, 1293525, 1293526, 1293527);
SummonHawkTriggered Ranked(1293248, 1312639). Bonus from the same file: Arcane …14287 (r8),
Serpent …25295 (r9), Hunter's Mark …14325, Aspect of the Hawk …25296, Raptor …14266,
WingClip …14268, StriderKick 1317257, Aspect of the Falcon 469145, Rapid Fire 3045, Feign Death 5384.

What we have: both tables deliberately empty (`classes/hunter.lua:137-146`), documented UNCONFIRMED,
F1/F2 silent by construction.

Verdict — advance status to SIM-CONFIRMED / CLIENT-UNCONFIRMED, wire nothing yet. Wire rule:
each id individually confirmed via in-client `GetSpellInfo` on 1.60.x before entering the table
(note: 1293248/1312639 are summon-effect ids, not castable — they inform the count probe, not the
cast table). Same probe session should also settle the Multi/Aimed filler conflict: the sim default
APL prompts Multi 2643 + Arcane 14287 + Aimed 20904 with weave guards, but ships
Use Aimed Shot=false / Use Summon Hawk=false (fetched valueVariables) — the audit's sharpest
Forever conflict needs a client-side answer, not a sim re-read.

## 5. H2 sim query → NO APL LUST-BRANCH EXISTS; RECOMMEND CUT (ORCHESTRATOR DECIDES)

Query answered: none of the three APLs read (TBC default, SoD p7_weave, Forever default) contains
any Bloodlust/Haste branch — verified in the fetched JSON above. All three model haste implicitly:
cast-time vs auto-time comparisons shrink automatically as cycles shorten. No APL suppresses
Aimed/Multi under haste.

What we have: H2 suppresses rules 6a/6b while `lust_remaining > 0`, Steady flows through 6c
(`hunter_guide.lua:729-743`, gather `classes/hunter.lua:1233-1261`). ADDON-ORIGINAL per audit §H2.

Verdict — H2 is SIM-DIVERGENT: under haste the engine's own clip-math (live `synced_duration`
read) already suppresses only casts that genuinely don't fit, making the blanket 6a/6b
suppression redundant. Recommend CUT (delete suppression, let clip-math decide; sim-faithful;
touches 6a/6b H2 pins in `tests/hunter_guide_state.lua`). Alternative KEEP as documented
conservative (human-reaction argument under 30% haste) — but then mark SIM-DIVERGENT BY DESIGN
in the header. No middle option exists. Decision + re-pin owned by orchestrator/next lane.
