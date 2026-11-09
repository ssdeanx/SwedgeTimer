# Hunter TBC WeakAura map (docs/hunter-wa.json) — 2026-10-19

Desk: hunter-wa. Read-only extract of `docs/hunter-wa.json`
(group `TBC Hunter UI [Anniversary - by React] - Laxx Mod`, wago `eEJOoHci-`,
`tocversion` 20505 = TBC Anniversary) mapped against `classes/hunter.lua`,
`hunter_guide.lua`, `hunter_ui.lua`. No addon behavior changed: every
sim-consistent WA value was already wired, so this lane adds WA-observed pins
only; conflicts keep sim-wins; WA-only extras are filed, not built.
Validation owner: orchestrator.

Provenance rule: WA ids below are CLIENT-OBSERVED (the pack ran on a TBC
client) but SIM-UNCONFIRMED unless a wowsims citation agrees; sim citations
are from `bench/hunter_rotation_audit_2026-10-19.md` + `bench/hunter_open_2026-10-19.md`.

## 1. Rotation tables (WA `Attack Speed || Rotation` init + customText)

- Mode 1 Standard: 9 tiers `5:4:1:1` (>2.33) `5:5:1:1` (>1.95) `5:6:1:1`
  (>1.74) `1:1` (>1.27) `5:9:1:1` (>1.09) `2:3` (>0.90) `1:2` (>0.70)
  `2:5` (>0.57) `1:3` (else). Speed = `UnitRangedDamage("player")`.
- Mode 2 Melee Weave: 5 tiers `5:5:1:1 3w` (>1.83) `2:2 1w` (>1.62)
  `6:9:1:1 3w` (>1.22) `6:11:1:1 3w` (>0.94) `3:7 2w` (else).
- Mode 3 Dynamic: `IsItemInRange("item:8149", "target")` (Voodoo Charm, 5 yd)
  on an attackable target selects Mode 2, else Mode 1. Stored in
  `TBCHunterConfig.rotLogicMode` (shipped config value 2, author default 1).
- WA-internal note (not ours): init `defColor`s disagree with the shipped
  `authorOptions` color defaults (e.g. `5:4:1:1` init red vs options blue);
  the init table wins unless the user customized. We adopt neither.
- Verdict: FILED, not built. Our guide is a shot-decision engine (rule matrix,
  `hunter_guide.lua:196-296`), not a speed→string readout; a rotation-text
  readout needs options widgets, which are out of scope (no inert toggles).

## 2. Swing-timer modes + ticks (WA `TBC Hunter Options`, cast/GCD ticks)

- `SWTMode` 1 = Single Bar, 2 = Mirror split (`Swing Timer - Left/Right`).
  `swtCastTick` (default true, cyan), `swtGCDTick` (default true, purple),
  `swtBackgroundWarning` (default false), `dynamicSwingTimerColor` (true).
- Cast-tick math (all three `*- Cast Tick` auras, identical): reset on
  `SPELL_CAST_SUCCESS` spell 75 (stores `lastAutoStart`, `autoSpeed`);
  on `SPELL_CAST_START` for `GetSpellInfo(2643/19434/34120)` names,
  `tickPercent = (progress + castDuration) / autoSpeed` capped at 1, cleared
  on `UNIT_SPELLCAST_INTERRUPTED`. Multi fixed 0.5 s; Steady/Aimed
  `UnitCastingInfo` exact with 3.0/1.5 s fallbacks.
- GCD tick: native `Global Cooldown` trigger, shown as a moving tick.
- Mana: `UNIT_POWER_FREQUENT` 2 s tick on gain; `UNIT_SPELLCAST_SUCCEEDED`
  6.45 s tick on spend (WA comment asks "why?" — carries no authority).
- Auto Border & Delay: per Auto-75 success `delay = elapsed - rangedSpeed`.
- Verdict: FILED (bars.lua owns swing/tick presentation — out of scope).
  Direction matches our `hunter_window` cast/hidden-window maths; WA's live
  `UnitCastingInfo` + fixed-0.5 Multi confirms our 0.5 s Multi assumption.

## 3. Spell ids — WIRED, WA-observed == sim-consistent (pins added/held)

| WA use | Id(s) | Ours | Sim |
|---|---|---|---|
| Castbar reset / melee-swing trigger | Auto 75 | `AUTO_SHOT_ID` (`classes/hunter.lua:191`) | — (base spell) |
| Cast-tick weave names | 2643 / 19434 / 34120 | multi/aimed/steady tables | TBC Multi 27021 family; TBC Steady **34120** (`steady_shot.go`) |
| `CB.spellIDs.multiShot` full set | 2643, 14288, 14289, 14290, 25294, 27021 | `multi_shot_ids` (`classes/hunter.lua:36-38`) EXACT match — NEW pin this lane | TBC top rank 27021 |
| Aimed primary 19434 / Long 20904 | 19434, 20904 | `aimed_shot_ids` 19434..20904 (`classes/hunter.lua:50-52`) | Era ranks |
| Kill Command / BW / RF / Readiness slots | 34026 / 19574 / 3045 / 23989 | tables (`classes/hunter.lua:59-71,158`) + slots | KC 34026 first (`default.apl.json`) |
| Melee range token | Wing Clip 2974 (`C_Spell.IsSpellInRange`) | `WING_CLIP_ID` (`hunter_ui.lua:56`) + range helper (`hunter_ui.lua:810-875`) | — |
| Ranged token (dead-zone check) | Auto 75 `IsSpellInRange` | `ui.auto_shot_token` (`hunter_ui.lua:860`) | — |
| Sweet spot | item 8149 | NOT wired — FILED (needs compat item-range probe; compat out of scope). Same 5 yd question already answered by `CheckInteractDistance("target", 3)` (`hunter_ui.lua:857`). | — |
| Viper (Aspect list) | 34074 | `viper_ids` {34074, 415423} (`classes/hunter.lua:173`) | TBC Viper 34074 (`default.apl.json` Mana group) |

## 4. CONFLICT — Arcane rank (sim wins, WA loses)

- WA `Arcane Shot` primary slot: `spellName` **14287** (lower TBC rank,
  CLIENT-OBSERVED). Sim TBC APL: **27019** core filler
  (`bench/hunter_rotation_audit_2026-10-19.md` §TBC). Our
  `arcane_shot_ids` = {27019, 49045} (`classes/hunter.lua:115-117`).
- Verdict: 14287 stays OUT by design (sim-optimal rank only); NEW pin this
  lane asserts the absence with this citation. The TBC Arcane arm stays
  dormant (`TBC_ARCANE_ENABLED=false`, base set full 6/6) per prior lane.

## 5. WA quirks (recorded, never wired)

- `CB.spellIDs.autoShot = {75, 2973}`: 2973 is Raptor Strike R1, not an Auto
  rank — WA-side quirk; our 2973 correctly lives in `raptor_strike_ids`.
- `Raptor Strike` aura trigger 2 (`spellName` 1495, Mongoose Bite) is dead:
  its `customTriggerLogic` returns only `triggers[1]`.
- The `5:4:1:1`-style labels are WA's own cycle notation; no semantics
  decoded here (UNCONFIRMED beyond the labels).

## 6. Trap / debuff / buff ids — FILED (all CLIENT-OBSERVED, TBC)

- Trap state machines (CLEU `SPELL_CREATE`/`SPELL_SUMMON`/`SPELL_DAMAGE`/
  `SPELL_AURA_APPLIED`/`REMOVED`/`MISSED` + 60.1 s safety timers): Snake
  34600 (60 s placed / 15 s active), Explosive 13813 + effect 13812
  (60 s / 20 s fire patch), Immolation 13795 + effect 13797 (60 s / 15 s),
  Freezing 1499 + effect 3355 (60 s / 20 s × Clever-Traps mult),
  Frost 13809 + effect 13810 (60 s / 30 s × mult). Replacement lists are the
  other four trap names. Clever Traps talent probe: `GetSpellInfo(19239)`
  icon match on Survival tab, `trapMult = 1 + 0.15 × rank`.
- Debuff auras: Concussive 5116, Wing Clip 2974, Stings 3043/1978/3034,
  Intimidation 19577, Scatter 19503, Silencing 34490, Wyvern 19386,
  Expose Weakness 34501, Hunter's Mark 1130. Utility/buffs: Aspects
  13165/5118/13159/34074/13163/13161/20043, Feed Pet 1539, Feign Death 5384,
  Misdirection 34477, Mend Pet 13544, Intimidation buff 24394, LotP
  34299/24932, GoA 25360 (missing check vs 25359), Bloodlust 2825/32182,
  Drums 35476, RF buff 3045, Quick Shots 6150, Beast Within 34692,
  4P T3.5 37482, Racials 20572/20594/20580/20549/20554/28730/28880,
  Flare 1543, Distracting 20736, Viper Sting 3034, Aimed Long 20904,
  Volley 1510, Scare Beast 1513, Traps tracker 14311 (meaning UNCONFIRMED).
- Verdict: FILED. Guide engine correctly has no trap arm
  (`bench/hunter_open_2026-10-19.md` §1 → LnL badge only, built); pet/mana
  alerts and buff rows are HUD/practice shape (out of scope).
- H2 CUT holds: WA `[BUFF] Bloodlust` is display-only; no
  Bloodlust/Heroism-family suppression exists in our hunter files
  (verified: no 2825/32182/35476 scan; pins in
  `tests/hunter_state.lua:2168-2205`, `tests/hunter_guide_state.lua:849-889`).

## 7. Lane diff (operator TBC-name fact + WA pins)

- `classes/hunter.lua`: `spell_token()` (TBC name / Era id for IsCurrentSpell,
  IsSpellKnown, GetSpellCooldown, IsSpellInRange, IsAutoRepeatSpell,
  IsSpellUsable) + `queue_tokens()` (TBC distinct family names, Era rank ids);
  applied to the queue loops, Auto sync/repeat, Viper knowledge, guide
  cooldowns, `resolve_known`, target range, HUD cooldown/usable queries. Id->name
  leg is `GetSpellInfo` (WA-proven on TBC); unknown names hide, never bare ids.
  No new gates: KC/BW/RF existence checks and SoD/Wrath/Forever paths unchanged.
- `hunter_ui.lua`: `resolve_spell()` returns name-or-nil on TBC (Era keeps the
  id fallback); WA id->name mapping recorded in the comment.
- `tests/hunter_state.lua`: WA cross-check block (Multi six-rank exact set +
  14287-absent) + §10b TBC/Era resolution pins (queue/viper/auto/cooldown/
  range/UI tokens) + §10c UI token pins + fixture token recorders.
- `tests/hunter_guide_state.lua`: TBC cooldown stub made name-aware (mirrors
  the TBC client; id-keyed fixtures keep working).
- `hunter_guide.lua`, `tests/practice_state.lua`: untouched (pure engine has
  no API tokens; weave steps carry no ids).

## 8. WA ids that needed names on TBC (converted, mapping pinned)

- Every WA `GetSpellInfo(id)` / `spellName` id already resolves through the
  name path above: 75 Auto Shot, 2974 Wing Clip, 2973 Raptor Strike, 2643
  Multi-Shot, 19434 Aimed Shot, 34120 Steady Shot, 34026 Kill Command, 19574
  Bestial Wrath, 3045 Rapid Fire, 23989 Readiness, 34074 Aspect of the Viper.
  The Arcane conflict (§4) dissolves on the read path: WA's 14287 and the
  sim-optimal 27019 share the name "Arcane Shot", so name-based cooldown
  reads count whatever rank the player knows (the id table keeps 27019 only).
- H2 CUT holds: verified no lust scan was added (grep: no 2825/32182/35476
  reads in hunter files); WA `[BUFF] Bloodlust` stays display-only.
