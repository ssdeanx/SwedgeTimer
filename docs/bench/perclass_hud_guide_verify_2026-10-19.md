# per-class HUD / guide / rotation-label / designmode verification 2026-10-19

Desk: hud-guide-gaps. Scope ONLY: classes/*.lua, root *_guide.lua, twist.lua,
weave.lua, nextaction.lua, druid_energy.lua, class *_state.lua +
*_guide_state.lua tests, tests/bars_state.lua (count pins ONLY for widgets
added — none added, file untouched). No other files touched. No git.

Method: read in-tree per class (HUD slots complete, guide provider live,
rotation label wired, designmode integration present). Harness baseline
verified green before and after: `bash tests/run.sh` 37/0, luacheck 2/0
(75 files) — no code changes, so no new mutations owed. Validation owner:
orchestrator. In-client behavior UNCONFIRMED throughout.

## 1. HUD slots + get_hud_state (frozen contract hud.lua header)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `classes/druid.lua:1802` HUD_SLOTS (6 rotational + TF/Berserk + 2 trinkets); `:1986` get_hud_state (reused table, nil-safe, TF/Berserk liveness gates) |
| HUNTER | WIRED | `classes/hunter.lua:1447` HUD_SLOTS (steady/raptor/kill_command/multi/bestial_wrath/rapid_fire/aimed + 2 trinkets); `:1561` provider (GCD swipe, mana/range tints, KC glow, ISS tint) |
| PALADIN | WIRED | `classes/paladin.lua:3011` HUD_SLOTS (cs/judgement/consecration/exorcism + 2 trinkets + wings); `:3178` provider (practice-aware, GCD echo filter) |
| SHAMAN | WIRED | `classes/shaman.lua:2844` HUD_SLOTS (stormstrike/flameshock/weave/firenova/earthshock/twist + 2 trinkets); `:2951` provider. NOTE: guide grew to 13 slots (`:2801`), HUD mirrors the original six by design — see §5 follow-up SH-1 |
| WARRIOR | WIRED | `classes/warrior.lua:2719-2724` family slot sets + `:2732` resolve_guide_slots (arms/SoD re-pick); `:2894` provider (GCD swipe, mana/range tints, OP/Execute glows) |
| ROGUE | WIRED | `classes/rogue.lua:931` HUD_SLOTS (snd/rupture/ea/ar/bf/tea/kick + kidney/restealth/bandage + 2 trinkets); `:1003` provider (reused table, aura/cooldown branches, secret-regime hide) |

All six providers clear the reused table every call (nil = not reported),
never guess on unreadable data. No missing HUD slot in scope.

## 2. Guide provider + gather_guide_inputs (contract nextaction_ui.lua:13-82)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `classes/druid.lua:1750` guide (6 slots + gather + evaluate + labels); `:1594` gather (reused table, per-field nil discipline) |
| HUNTER | WIRED | `classes/hunter.lua:1398` guide (family slot sets); `:1106` gather (reused table) |
| PALADIN | WIRED | `classes/paladin.lua:2885` guide (cs/soc/sob/twist/judge/consecration/exorcism/how); `:2625` gather |
| SHAMAN | WIRED | `classes/shaman.lua:2801` guide (13 slots incl. feralspirit/fireele/magma/lavalash/shamanisticrage/chainlightning/moltenblast); `:2536` gather |
| WARRIOR | WIRED | `classes/warrior.lua:2646` guide (family sets + composite rage gate); `:2416` gather |
| ROGUE | WIRED | `classes/rogue.lua:692` guide (builder/rupture/eviscerate/envenom/expose/shiv/tea + M6 unknown ownership); `:760` gather (energy/CP nil-safe, tick predictor, SoD latch, ea_duty, TTD, aura/usable/cooldown reads) |

All six expose slots + gather + evaluate + labels; all gathers write into a
caller-owned reused table; all evaluates guard the missing-engine case
inert. Rogue `inputs.G`/swing speed absent by design (energy-tick model;
no rule in `rogue_guide.lua` reads G) — follow-up question for the engine
owner, not a gap.

## 3. get_rotation_key (contract rotationtext.lua:18-24)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `classes/druid.lua:2092`; pins `tests/rotationtext_state.lua:600-617` |
| HUNTER | WIRED | `classes/hunter.lua:1654`; pins `:558-574` |
| PALADIN | WIRED | `rotationtext.lua:222` (documented deviation: lives in rotationtext.lua, pure cut-and-paste; do not move without pins); pins `:237-296` |
| SHAMAN | WIRED | `classes/shaman.lua:3034`; pins `:623-637` |
| WARRIOR | WIRED | `classes/warrior.lua:2994`; pins `:580-594` |
| ROGUE | WIRED | `classes/rogue.lua:1595` (hunter shape); pins `tests/rogue_state.lua:1424-1483,1577` + `tests/rotationtext_state.lua:640-678` |

`RT.provider` (`rotationtext.lua:189-195`) resolves by `player_class` key.
No class missing. Paladin location deviation is pre-existing and pinned.

## 4. on_bar_update driving guide + HUD in order

- DRUID `classes/druid.lua:1270` — guide `:1294` then hud `:1302`. WIRED.
- PALADIN `classes/paladin.lua:1372` — guide `:1401` then hud `:1408`. WIRED.
- SHAMAN `classes/shaman.lua:2207` — guide `:2238` then hud `:2246`. WIRED.
- WARRIOR `classes/warrior.lua:2146` — guide `:2170` then hud `:2178`. WIRED.
- ROGUE `classes/rogue.lua:1489` — guide `:1518` then hud `:1524`, never gated on `st.is_mainline` (`:1489-1492`). WIRED.
- HUNTER `classes/hunter.lua:402` — hud `:418` runs BEFORE guide `:441` (reversed vs all five siblings). D1 CLOSED as documented behavior per five-class-gaps lane (independent frames, neither consumer reads the other's output; reorder would be purposeless churn). No code change.

Call sites guarded (`bars.lua:680-682` H2 fix); a throw in either consumer is
isolated regardless of order.

## 5. Design / designmode integration

- Visuals builders present: DRUID `setup_druid_visuals` (`classes/druid.lua:1100`); HUNTER `hunter_ui` widget set (`classes/hunter.lua:425-426` + `hunter_ui.lua`); PALADIN `setup_twist_visuals` (`:1244`) + seal icons/band/JotC/CD row; SHAMAN `setup_weave_visuals` (`classes/shaman.lua:1094`); WARRIOR `setup_warrior_visuals` (`classes/warrior.lua:1442`) incl. W1 desync spark (`:1601`); ROGUE `setup_rogue_visuals` (`classes/rogue.lua:1182`, spark/wash/SS/swap/poison).
- bars_state boot pins cover all six (`tests/bars_state.lua:835-877` counts + `:954-1017` visual-creation cases; ROGUE `:870-876,1010-1017` present — D3/D4 CLOSED).
- option_table_presets branches exist for all six (`option_table_presets.lua:1044` DRUID, `:1085` HUNTER, `:1123` PALADIN, `:1176` ROGUE, `:1203` SHAMAN, `:1242` WARRIOR).
- LGC needs no per-class wiring (central `main.lua:47,392-395`); GCD markers are bar-level defaults (`config_presets.lua:161-211`).

## 6. Root pure modules

- `twist.lua` (paladin twist window/attempt/success/impossible + SoD 0.2 s narrow + ICD 1 s + reseal fraction): WIRED, pins `tests/twist_state.lua` 84-86 checks.
- `weave.lua` (shaman breakpoint/safe-window/haste/Maelstrom + MW5 guard + family ICD): WIRED, pins `tests/weave_state.lua` 465 checks.
- `nextaction.lua` (paladin rotation tables + TBC pull-hold/reseal-guard + FCFS + Forever echo + SoD execute): WIRED, pins `tests/nextaction_state.lua` 477 checks.
- `druid_energy.lua` (tick fraction, proc-aware gain, TTD EMA + format, GCD tick): WIRED, pins `tests/druid_energy_state.lua` 70 checks.
- Per-client guides: `warrior_guide.lua`, `druid_guide.lua`, `shaman_guide.lua`, `hunter_guide.lua`, `rogue_guide.lua` — all present, all consumed only through the guarded `guide.evaluate` above; per-engine suites green (warrior 1007, druid 95214, shaman 765, hunter 1115, rogue 433).

## 7. Filed follow-ups (need files OUTSIDE this lane's scope — reason each)

Nothing in §1–§6 above needs an in-scope edit. Every remaining gap needs
an out-of-scope file, so it is filed here, not wired:

- R-1 (rogue): snd/ar/bf guide icons (slots 8-10) + `guide_contract` 7-slot pin update + `nextaction_ui` mapping. Needs `guide_contract` (OUT) + `nextaction_ui.lua` (not in scope list) + options widgets. Engine side ships slot-less (NOW + rotation label). Source: `bench/rogue_rotation_gaps_closed_2026-10-19.md` #1.
- W-1..W-8 (warrior): Sunder upkeep slot, Rend upkeep outside Wrath-arms, SoD OP stance-dance, stance system (compat probe + main wiring), Wrath-50/SoD-60 floor decision, Victory Rush (UNCONFIRMED, SKIP per operator), Hamstring prompt rule + slot + options. Need slots (`guide_contract` OUT) + options (`option_tables`/`config_presets` OUT) + compat/main (OUT). Source: `desks/warrior-rotfix/journal.md` follow-ups (a)–(h).
- D-1..D-8 (druid): fight-elapsed input (needs `main.lua` combat-start stamp OUT), trick windows (tick-phase + live-cost inputs), Wrath/SoD clipRoar-glyph + Rake DPE (glyph/set/AP inputs), Omen-fishing FF (FF cooldown input), W1 latency term (probe), Forever Berserk/Claw/consumable (id confirm + slot/sequence design, contract + options OUT), TBC RipCP threshold (option OUT), TBC RakeTrick/bear + Cata/Mists + UNCONFIRMED numbers (in-client proof). Source: `desks/druid-rotfix/journal.md` follow-ups 1–8.
- S-1..S-12 (shaman): FS refresh default, autocast-CD cue, CL enemy-count sensor (compat probe OUT), buff-keyed twist + GoA WF-buff gate, TBC twist mana-pause, Fire Ele snapshot cue, Forever static totem + Searing maintain (totem-id + fight clock), per-client SS swipe fallback, WF-hold/SR/ES-floor options, Wrath sim lane, wiring crossfire. Need options/config (OUT) + compat (OUT) + HUD (`hud.lua` OUT). Source: `desks/shaman-rotation-fix/journal.md` follow-ups (1)–(12).
- P-1.. (paladin): SoC Rank-1 advice (new UI slot + option), Era Judgement-stopattack (macro/UI), Era prepull (`main.lua` OUT), SoD seal-maintenance (new guide slot + `nextaction_ui` + provider map), SoD twist/Shockadin/Wrath-like variants (selector + options + dispatch), fight_remaining provider source, how_cast_seconds probe (compat OUT), twist_mana_threshold value (option OUT), strictSequence hard-wait (`nextaction_ui`). Source: `desks/paladin-fixes/journal.md` filed list.
- H-1.. (hunter): LnL proc (56344/415413 SIM-CONFIRMED, needs compat target-aura scan OUT), Serpent debuff + Sniper buff (compat OUT), TBC Arcane arm dormant (needs slot + options OUT, contract full), Forever Sniper/Hawk ids (SIM-CONFIRMED only, need 1.60.x `GetSpellInfo` in-client proof) + hawk-count source + HHA sequence, TBC melee-weave/move cues + trap-weave timing + ISS/Readiness display (HUD/bars OUT), mana/Viper/prepull/mark/aspect/Sniper-Training (compat/mana/options OUT), H2 lust-suppression sim query (UNCONFIRMED), TBC Steady-34120 downrank + Wrath Explosive ranks (no id change here). Source: `desks/hunter-rotation/journal.md` + `bench/hunter_open_2026-10-19.md`. **CORRECTED 2026-10-20** (desk `corpus-corrections`): the TBC Steady id is settled — **56641 does not exist on the TBC client** (the TBC APL casts 34120) and the **Forever client has no Steady Shot at all**; the Wrath rows' APL ids are **61006** (Kill Shot) and **60053/60052** (Explosive Shot) — the build lane re-cut the rotation table's rows (`bench/hunter_apl_utility_build_2026-10-20.md` §3; `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **H1**–**H4**).
- SH-1 (shaman HUD mirror): the 7 post-Wrath guide slots (feralspirit/fireele/magma/lavalash/shamanisticrage/chainlightning/moltenblast) have no HUD mirror; `classes/shaman.lua:2829-2833` documents the deferral (`hud_state.lua` pins the eight-slot row). Adding HUD slots needs `classes/shaman.lua` (in scope) PLUS `tests/hud_state.lua` pins (OUT) + options (OUT) — cannot land HUD-only without breaking the frozen HUD suite. Filed for a lane that owns `hud.lua` + `hud_state.lua` + options together.
- OPT (all classes): owed option widgets for every nil-safe `== true` / `~= false` key added by prior lanes (hunter_target_warning, report toggle/button, druid TTD/reseal, warrior desync/commanding, rogue thresholds, shaman FS/autocast/CL/mana-pause/Fire-Ele/totem/Searing/swipe/WF-hold/SR/ES, paladin SoC/Judge/prepull/SoD/fight_remaining/how/mana/strictSequence, hunter LnL/Serpent/Sniper/Arcane/Hawk/mana/Viper). `option_tables.lua` + `config_presets.lua` are OUT for this lane — filed for the options pass with defaults documented in the owning lane journals (nil = off unless stated).
- D1 (hunter order): CLOSED, no follow-up (documented behavior, §4).
- D2 (rogue empty `SPELL_IDS`/`POISON_IDS` `classes/rogue.lua:116-117`): BY DESIGN (readiness rule: ship empty, fill in-client; HUD greys-missing, never guesses). Becomes actionable only with the poison/Shiv CLEU matching lane (ids UNCONFIRMED until a client confirms them).

## Verdict

ADEQUATE. All four systems WIRED for all six classes in-tree; no in-scope
wireable gap remains. Every open item above names the out-of-scope file
that owns it and the reason this lane could not take it. Harness 37/0 +
luacheck 2/0 re-verified on the untouched tree; zero files changed, zero
new pins owed, zero mutations owed (no behavior changed).

Limitations: offline verification only. In-client timing, `/dump`
slot-types, live lust/haste windows, and all TESTING.md visuals are
UNCONFIRMED and belong to the owner in-client test session.
