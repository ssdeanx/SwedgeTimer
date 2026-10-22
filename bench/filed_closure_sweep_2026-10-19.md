# bench/filed_closure_sweep_2026-10-19.md — the filed-item closure sweep (Phase 6)

Desk: `filed-closure-sweep`. Date: 2026-10-19.
Plan: `bench/final_completion_plan_2026-10-19.md` **Phase 6** — "Every item filed 'with reason'
… is re-examined: close whatever is closable with a source; keep the rest filed with a sharper,
testable reason. Read-only research first, then build lanes for the closable ones."

**Scope of this file.** One new bench artifact. No addon file, no test file, no other bench file
was modified. No git write of any kind was performed on the addon repo. The only git commands
run were **read-only** `git show` / `git grep` against the external client-source mirror
`/home/sam/wow-ui-source` (explicitly sanctioned by the Phase-6 brief) plus read-only fetches of
public wowsims / wowhead sources.

**Evidence bar used here** (the strongest first):

1. **CLIENT-SOURCE** — the shipped client's own FrameXML, read via
   `git -C /home/sam/wow-ui-source show <branch>:<path>`. Branches used, with their client
   versions (`version.txt`): `classic_era` = 1.15.9.70003, `classic_anniversary` = 2.5.6.70006,
   `classic_titan` = 3.80.2.69815 (the WotLK/Titanforge client the addon targets),
   `origin/forever` = 1.60.1.70374, `live` = 12.1.0.69814.
2. **SIM-CONFIRMED** — a wowsims file fetched live this session (URL given), with the quoted line.
3. **WEB-CONFIRMED** — a wowhead / warcraftdb page whose **redirect slug + page title** were
   observed this session (the slug is the spell's canonical name, so it is a name source, not a
   guess).
4. **IN-TREE** — the shipped addon's own file:line (the item was already closed, or the
   premise of a filing is stale).

Anything that is not one of the above is marked **STILL-FILED** with the exact missing evidence
named. No id, number, sim line or client path is asserted without one of the four.

**What this file is NOT.** It is not a code change and not a validation. Every build spec in §7 is
a *specification* to be built by a named lane; the orchestrator validates in-tree. No in-client
observation was made by this desk (the operator's session remains the only in-client truth).

---

## 1. Verdict summary

| Corpus | Rows | CLOSABLE | CLOSED (already / by ruling) | STILL-FILED | other |
|---|---|---|---|---|---|
| A — `deep_audit` F1–F14 + justified exceptions | 16 | 0 | 14 | 2 | — |
| B — `class_features_drills` §5 U-01…U-15 | 15 | 10 | 1 | 4 | — |
| C — per-lane filed lists (6 classes) | 91 | 23 | 32 | 35 | 1 operator decision |
| D — `ids_research` U1–U17 | 18 | 8 | 3 | 6 | 1 correction |
| **Subtotal (A–D)** | **140** | **41** | **50** | **47** | **2** |
| E — `live_test_script` U1–U17 (a different axis: *offline*-closable?) | 17 | 5 fully + 7 partly | 1 moot | 4 operator-only | — |

**How to read the counts.** The **CLOSED** column is dominated by items earlier lanes already
landed — this sweep's job there was only to *verify* the closure in-tree (read the code, not the
report). The value of this sweep is in the **41 CLOSABLE** rows: 19 of them need code (the nine
build specs in §7), and the remaining 22 are **ledger/doc closures** — a source now exists where
the filing said none did, so the *filing* can be struck and the citation written down (no lane,
no code). The **47 STILL-FILED** rows all carry a sharper reason and a named closing evidence in
§8.

**Headline results of this sweep (things that were filed and are now CLOSABLE):**

- **S-20 Call of the Elements is no longer blocked on evidence.** The id `66842` and the
  **water-totem slot `3`** are both in the *shipped client's own* `Constants.lua` — see §7 BS-4.
  `compat.lua` already exposes `api.GetTotemInfo(slot)` with the slot map documented.
- **The druid's Wolfshead blocker was a wrong premise.** `api.GetInventoryItemID` already exists
  in `compat.lua` and `GetInventoryItemID("player", invSlot)` is in the client's own FrameXML on
  every branch; `INVSLOT_HEAD = 1` is in the client's `Constants.lua` — see §7 BS-2.
- **The hunter's Serpent Sting debuff read is not an API gap.** `api.UnitAura(unit, index, filter)`
  is *unit-generic*; only the target scan is missing — see §7 BS-3.
- **The rogue's "Hemo" name is not uncertain — it is "Hemorrhage",** and the bench's TBC id pairing
  is **swapped** (26862 = Sinister Strike, **26864 = Hemorrhage**) — see §7 BS-6 and §9-N1.
- **The paladin's Forever "no sourced id" is stale:** 10333 (Holy Strike), 1311703 / 1311704
  (Echo of Command / Righteousness) are in `bench/ids_research_2026-10-19.md` §2 — §7 BS-5.
- **The SoD p4-twist APL path is now known and fetched** (§5 U5), and the TBC enhancement APL
  (the FS 12 s line) is fetched and quoted (§5 U4).
- **The Shaman Flame Shock refresh default flip (3 → 0) is unblocked** — the sim finding is
  already written into `config_presets.lua:1031-1035`; only the value and its pin remain (§7 BS-4c).

---

## 2. Table A — `bench/deep_audit_2026-10-19.md` (F1–F14 + the justified exceptions that owe)

| # | Filed item | Verdict | Closing source / sharper reason |
|---|---|---|---|
| F1 | `install_error_handler` has no caller → "errors none" is a false negative | **CLOSED** | `main.lua:631-632` calls `st.diag.install_error_handler()`; `main.lua:1102-1103` uninstalls on logout. Pins: `tests/diag_state.lua:660,662,797,804,811,855,861`. |
| F2 | `PLAYER_TARGET_SET_ATTACKING` registered but `self.has_oh` never true → dead handler | **CLOSED** | `has_oh` is now derived from the offhand probe, not hand-set. Pins: `tests/main_init_state.lua:1671` ("F2: has_oh is derived from the offhand probe, not hand-set"), `:1712,1723,1727,1737`. |
| F3 | the report's only output path is the bare global `print` | **CLOSED** | `diag.lua:116-143` — falls back to `st.utils.print_msg` and announces the fallback once. |
| F4 | `compat.get_family_spell_id` probes with numeric ids; TBC resolves by name; callers latch false | **CLOSED** | `bench/f4_family_spell_id_2026-10-19.md` (compat-f4 lane): the walk goes through `api.get_spell_query` and `api.get_family_spell_id_state` separates resolved / absent / unresolved. |
| F5 | `HUD.cleu_register_errors` is a write-only counter (no reader) | **CLOSED** | `main.lua:1804-1808` prints `hud_cleu_register_errors=N` in the runtime diag line. Pins: `tests/main_init_state.lua:1782-1788`. |
| F6 | base TOC advertises mainline interfaces and ships the classic combat-log lib | **CLOSED** | the base TOC was narrowed to classic-line (audit-f6-toc lane; `tests/toc_check.lua` 816/0). |
| F7 | `ST:needs_gcd()` has no callers; AceDB `**` auto-creates the tables it reads | **CLOSED** | deleted from `main.lua`. Pin: `tests/main_init_state.lua:1793-1798` ("F7: the dead needs_gcd helper is gone from main.lua"). |
| F8 | hunter runs HUD before guide; the other five run guide first | **CLOSED** | class-order-parity lane — guide → HUD → practice in all six. |
| F9 | paladin's `post_init` order differs (guide→practice→HUD) | **CLOSED** | same lane as F8. |
| F10 | `run_guarded` implemented six times with six quarantine constants | **CLOSED** | `guard.lua` is a new root module on all 7 TOCs: `st.guard.run/label/note/refusal/quarantined` (`guard.lua:37,41,109,132,145,170`). Consumers: `bars.lua:522-524,549,664,680`; `hud.lua:215,1190`; `nextaction_ui.lua:736,787,802`; `rotationtext.lua:251,473`; `practice_ui.lua:866,5577,5581,5585`. |
| F11 | `assert(event == event)` used as a luacheck "unused argument" silencer in 7 handlers | **CLOSED** | zero occurrences remain in the tree (grep over all non-`Libs/` `.lua`); the handlers use a named `_event` parameter. Pin: `tests/main_init_state.lua:1800+`. |
| F12 | raw global `print` in a live error path (`bars.lua:1185`) | **CLOSED** | zero `print(` calls remain in `bars.lua` (grep); the path uses `st.utils.print_msg`. |
| F13 | `table.remove(list, 1)` inside a trim loop → O(n²) memmove on the combat path | **STILL-FILED** | **Sharper reason.** The sites are still live and are now enumerable exactly: `classes/hunter.lua:833`, `classes/warrior.lua:1316`, `classes/druid.lua:3218`, `diag.lua:551`, `practice.lua:1411`, `practice_stats.lua:294,364,576,616`, `practice_progress.lua:603,1243`. What is missing is **not** evidence but a *decision*: the audit says "caps are small, so bounded today" — the cap sizes were never written down, so "bounded" is an assertion, not a measurement. **What would close it:** (a) the per-list cap constant for each of the 10 sites, and (b) the worst-case cost per event (cap² memmove), or a conversion of the 4 combat-path sites (`hunter`/`warrior`/`druid`/`diag`) to an index-offset ring. Until the caps are cited, "bounded" is not testable. |
| F14 | `practice_stats.lua` / `practice_progress.lua` are on no TOC → the whole progress feature is a silent no-op | **CLOSED** | `SwedgeTimer.toc:55-56` list `practice_stats.lua` then `practice_progress.lua` (and every flavour TOC). |
| JE-1 | justified exception: the paladin's `pcall(LCD.Register…)` degrade is **invisible to `/st diag`** (an F5-style gap the audit itself names) | **STILL-FILED** | **Sharper reason.** There is no counter and no notice on the paladin's `LCD.Register` failure path, so a player sees the guide frame simply not appear, with no diagnostic. **What would close it:** a counter in the paladin provider, surfaced on the `main.lua` runtime-diag line in the same shape F5 got (`hud_cleu_register_errors=N`). This is a two-file build (see §7 BS-8) — the *evidence* is not in doubt, the counter is simply missing. |
| JE-2 | justified exception: raw `world_ms` used in weave/twist maths | **CLOSED (documented rule)** | This is a recorded design decision, not a debt: raw latency is the sim's own `Latency` setting and the calibrated reading is a display-alignment correction only (`classes/druid.lua` W1 latency note, `bench/druid_drills_2026-10-19.md` DU-22). No closure owed. |

---

## 3. Table B — `bench/class_features_drills_2026-10-19.md` §5 (U-01 … U-15)

| # | Item | Verdict | Closing source / sharper reason |
|---|---|---|---|
| U-01 | Warrior **rage regeneration rate** (the scenario's rage ledger) | **STILL-FILED** | **Sharper reason, now proven:** *no* wowsims warrior model contains a rage-regeneration term, so a sim citation is **impossible**, not merely missing. Fetched this session: `wowsims/classic sim/core/rage.go` (rage is gained **only** from damage dealt `damage*7.5/rageConversion` and damage taken `result.Damage*2.5/rageConversion`; no periodic regen), `wowsims/classic sim/warrior/warrior.go` (no regen constant), `wowsims/sod sim/warrior/warrior.go` (none), `wowsims/wotlk sim/core/rage.go` + `sim/warrior/warrior.go` (none). The shipped 10/s at `practice.lua:2274` is therefore an **addon model**, not a sim value. **What would close it:** (a) an in-client measurement — `UnitPower("player", 1)` delta over 1 s in combat (operator probe, or a compat probe on a debug branch), or (b) a cited non-sim source that states the client's rage regen. Until one of those exists the model must stay labelled as an addon model wherever it is quoted. |
| U-02 | Druid **powershift refund (40) and regen (10/s)** | **CLOSABLE (regen half) / STILL-FILED (refund half)** | **Regen CLOSABLE:** the sim's own energy-tick model is the source — `wowsims/classic sim/core/energy.go` (fetched this session) declares `EnergyTickDuration = time.Millisecond * 2020` and `EnergyPerTick = 20.2`, i.e. exactly **10.0 energy/s** (20.2 / 2.02). The addon's `druid_energy.lua` freezes 2.0 s / 20 — the same rate, but the sim master has drifted to 2020 ms / 20.2; the *rate* is unchanged, the *cycle* is not, so a citation should carry both. **Refund STILL-FILED:** the 40 is a "Furor-5/5 model" constant, and the Furor talent id has no source (§8 item W-1). |
| U-03 | Druid **Wolfshead 8345** | **CLOSABLE** | **The filing's premise is false — the read path already exists.** `compat.lua:986` `api.GetInventoryItemID(slot)` (wraps the classic global `GetInventoryItemID`, secret-safe). The global is in the client's own FrameXML on **every** branch: `classic_era:Interface/AddOns/Blizzard_FrameXML/Wrath/EquipmentManager.lua:88,170,279,325`; `classic_titan:` same file/lines; `classic_anniversary:` same; `origin/forever:Interface/AddOns/Blizzard_BoostTutorial/Blizzard_TutorialLogic.lua:1149,1305`; `live:` same. The **head slot number** is also client-sourced: `classic_era / classic_titan / classic_anniversary: Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:173` → `INVSLOT_HEAD = 1;` and `origin/forever:Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:136` → `INVSLOT_HEAD = 1;`. The id itself is WEB-CONFIRMED: `bench/ids_research_2026-10-19.md` §2 (`8345` → wowhead `item=8345/wolfshead-helm`, "Wolfshead Helm (item)", TBC, sim `HasItemEquipped(8345)`). Build: §7 BS-2. |
| U-04 | Rogue **Hemo builder** (excluded as an uncertain name) | **CLOSABLE** | The name is **"Hemorrhage"**, and the id pairing in the bench corpus is **wrong**: wowhead's own redirect slug + page title (observed this session) — `https://www.wowhead.com/tbc/spell=26864` → **301** → `/tbc/spell=26864/hemorrhage`, title "Hemorrhage"; `https://www.wowhead.com/tbc/spell=26862` → **301** → `/tbc/spell=26862/sinister-strike`, title "Sinister Strike"; `https://www.wowhead.com/tbc/spell=26863` → `/backstab`; `.../26865` → `/eviscerate`; `.../26867` → `/rupture`; `.../34413` → `/mutilate`; `.../26889` → `/vanish`; `https://www.wowhead.com/forever/spell=16511` and `https://www.wowhead.com/classic/spell=16511` → `/hemorrhage`. So: **TBC Hemorrhage = 26864** (the bench says 26862) and **TBC Sinister Strike = 26862** (the bench says 26864) — the two are swapped in `bench/class_features_drills_2026-10-19.md:609`, `bench/rogue_rotation_audit_2026-10-19.md:72` and `bench/ids_research_2026-10-19.md` U10. Build: §7 BS-6; the correction is §9-N1. |
| U-05 | Rogue **per-CP Rupture durations 2–4 CP** | **STILL-FILED** | **Sharper reason.** Two separate things are needed and neither exists: (a) the **remaining sim rows** (1 CP = 8 s and 5 CP = 16 s are the only sourced rows, `rogue_guide.lua:348`), and (b) a **split of `min_ttd`** — the same value currently drives both the Rupture floor *and* the dying-target dump rule (`rogue_guide.lua:662`), so consuming a per-CP table would move the dump threshold too. **What would close it:** the per-CP duration rows from the wowsims rogue `rupture.go` (family by family) **plus** a decision to separate `min_ttd` from the Rupture duration table. A partial table would leave 2–4 CP on a flat floor — a discontinuity the data cannot justify. |
| U-06 | Hunter **Forever Sniper/Hawk ids** + the **hawk-count source** | **STILL-FILED** | The ids stay SIM-CONFIRMED-only: the client's own FrameXML on `origin/forever` carries **none** of 1310687 / 1293241 / 1293525 / 1293526 / 1293527 / 1293248 / 1312639 (grep over `Interface/AddOns` → 0 hits each), so there is no offline client source and the closure is the operator's 1.60.x `GetSpellInfo`. The **count source** is a separate, harder blocker: `bench/hunter_open_2026-10-19.md` §3 records that the sim *constructs* the hawks (`EffectN(3)`, 18 s, round-robin replacement) and never observes them. **What would close it:** one of (a) the number of "Summon Hawk" auras on the player, (b) guardian-pet enumeration (the client exposes no unit-token contract for the hawks), or (c) a combat-log summon count — and it must be proven by an in-client probe before any id is wired. |
| U-07 | Hunter **Serpent Sting target-debuff source** (the gather writes `serpent_known` / `serpent_active` nil) | **CLOSABLE** | **The API is not missing — the scan is.** `compat.lua:456-488` defines `api.UnitAura(unit, index, filter)`, which is **unit-generic** (the `unit` argument is already a parameter) and already secret-safe; `compat.lua:514-543` `api.scan_player_aura(predicate)` is the exact template a target scan needs (`"player"` → `"target"`, `"HELPFUL"` → `"HARMFUL"`). The current gather hard-codes the unknown: `classes/hunter.lua:2348` `inputs.serpent_active = nil`. Build: §7 BS-3. |
| U-08 | Hunter **TBC Steady rank 34120** | **CLOSABLE** | The id is WEB-CONFIRMED: `bench/ids_research_2026-10-19.md` §2 — `34120` → `https://www.wowhead.com/tbc/spell=34120/steady-shot` (TBC rank). The filing's real content — "the sim downranks for mana; we resolve the highest known rank" — is a **deliberate addon policy**, not an evidence gap, and the audit itself records it as LOW. Closure: the id is sourced; the policy is a one-line note, not a build. |
| U-09 | Shaman **per-family Stormstrike fallback** (Era 20 / SoD 6 / TBC 10 / Wrath 8) | **CLOSABLE** | The sim values are confirmed and one of them is re-confirmed this session: `wowsims/tbc-new sim/shaman/stormstrike.go` → `CD: core.Cooldown{ Timer: shaman.NewTimer(), Duration: time.Second * 10, }` (TBC = 10 s ✓), the debuff `Duration: time.Second * 12`, `MaxStacks: 2`, `BaseCostPercent: 8`. The blocker was never the number — it was that the two live consumers discard the full duration. The guide path *does* pass it (`nextaction_ui.lua:628` `local full = inputs[sf.duration_key] or sf.slot.swipe_duration`; the duration key is derived at `nextaction_ui.lua:367-371` from `slot.cooldown_key`), and the gather already writes the live duration (`classes/shaman.lua:2923-2924` `inputs.stormstrike_remaining, inputs.stormstrike_duration = get_guide_cooldown(...)`). What still needs the change is the **static fallback** `swipe_duration = 10` on the guide slot (`classes/shaman.lua:2675-2676`) and the HUD mirror's equivalent, which are the only paths that can show a wrong number. Build: §7 BS-4b. |
| U-10 | Shaman **water totem slot / CoE 66842** on 3.80.2 | **CLOSABLE** | **Decisive, and the "UNCONFIRMED" in the tree is stale.** The shipped WotLK client (branch `classic_titan` = 3.80.2.69815) carries both facts in its own `Constants.lua`: `Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:286-289` → `FIRE_TOTEM_SLOT = 1; EARTH_TOTEM_SLOT = 2; WATER_TOTEM_SLOT = 3; AIR_TOTEM_SLOT = 4;` and `:300-304` → `TOTEM_MULTI_CAST_SUMMON_SPELLS = { 66842, 66843, 66844 };` (the client's own list of shaman totem-summon spells — 66842 is in it). The same two blocks exist on `classic_era` and `classic_anniversary` (`:286-289`, `:300-304`) and on `origin/forever` (`Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:226-229` and `:240-244`). The **slot readers** are also client-sourced: `classic_titan:Interface/AddOns/Blizzard_UnitFrame/Classic/TotemFrame.lua:75` → `AuraButtonMixin.UpdateDuration(self, math.ceil(GetTotemTimeLeft(self.slot)))`, and `Interface/AddOns/Blizzard_APIDocumentationGenerated/TotemDocumentation.lua:56-77` → `GetTotemInfo(slot)` returns `haveTotem, totemName, startTime, duration, icon, modRate, spellID` and `GetTotemTimeLeft(slot)`. **And the addon already has the API**: `compat.lua:1076` `api.GetTotemInfo(slot)`, whose own comment (`compat.lua:1064`) already states "Slots are 1=Fire, 2=Earth, 3=Water, 4=Air (Blizzard_FrameXMLBase/Constants.lua:239-244)" — i.e. the water slot was never really unconfirmed. Build: §7 BS-4. |
| U-11 | Paladin **Holy-Power stack 1226461**, Templar/Sunlight, Aura-Mastery rune, dual-seal timers | **CLOSABLE (the ids) / STILL-FILED (the in-client behaviour, = U-14)** | The ids are WEB-CONFIRMED with page titles observed this session and recorded in `bench/sod_paladin_variants_2026-10-19.md` §0: `1226460` "S03 Scarlet Enclave Ret 2P Bonus (set-aura id; APL gates 'known')", `1226461` "Holy Power (stack aura; APL gates stacks == 3)", `1226464` "Templar (APL: wait-for-DS rule)", `1239543` "Sunlight (maintenance aura in shockadin APLs)", `1240574` "Templar (maintenance aura in shockadin APLs)", `407624` (Aura Mastery), `407798` "Seal of Martyrdom", `426157` "The Art of War", `429152` "Improved Hammer of Wrath (rune)", `467518` "S03 T2 Ret 2P Bonus (gates Judge in p8-wrath)", `1214298` "Libram of Sanctity", `1219193` "Naxx Ret 6P Bonus", `20930` "Holy Shock (APL uses rank 3)". The *behaviour* of those auras in the client is the standing U-14 caveat. |
| U-12 | Paladin **Holy Strike** id on Forever | **CLOSABLE** | WEB-CONFIRMED: `bench/ids_research_2026-10-19.md` §2 — `10333` → `https://www.wowhead.com/forever/spell=10333/holy-strike`, "Holy Strike (50% + 97-121 Holy)", Forever. (Note for the record: the wowhead `/forever/` pages are bot-walled to this session's scraper — HTTP 403 on a re-fetch — so the ids_research snippet is the standing source; the name "Holy Strike" is certain, and the addon resolves by name anyway.) |
| U-13 | Warrior **stance index map** and the SoD aura 426969 | **CLOSABLE (the stance map) / STILL-FILED (426969)** | **Stance map, SIM-CONFIRMED (fetched this session):** `wowsims/classic sim/warrior/stances.go` registers the stance **auras** as Battle `core.ActionID{SpellID: 2457}`, Defensive `core.ActionID{SpellID: 71}`, Berserker `core.ActionID{SpellID: 2458}`; `wowsims/tbc-new sim/warrior/stances.go` carries the same three ids. **Aggressive Stance is absent from both sims** — so the addon's "unknown stance withholds nothing" behaviour (`classes/warrior.lua:572-577`) is *sim-exact*, not a gap. The shipped ids match (`classes/warrior.lua:315-323`). The **SoD aura 426969** stays filed: no client source (grep over the four classic branches → 0 hits) and the sim does not model it. |
| U-14 | All **in-client** behaviour of every sim number | **STILL-FILED (standing)** | By construction this is the operator's session, not a research item. It is now *narrower*: after §3/§4 the only things that still need in-client truth are the **behaviour** of confirmed ids and the **client-unconfirmed id sets** (U1, U9-partial, U10-partial, U11-behaviour, U12-shaman, U13-warrior, U14-druid) — not the numbers themselves. |
| U-15 | Every **grading band** in §2 | **CLOSED (policy)** | `[DESIGN]` — addon policy, deliberately not sim-sourced. Nothing to research; the bands are pinned in the class suites. |

---

## 4. Table C — the per-lane filed lists

### 4.1 Shaman (`bench/shaman_slots_2026-10-19.md` §2 + `bench/shaman_drills_2026-10-19.md` §2)

| Item | Verdict | Closing source / sharper reason |
|---|---|---|
| S-19 Lightning Shield — **live guide slot** | **CLOSED** | Built by the shaman-slots lane: slot 16, rule 11b, HUD mirror (`bench/shaman_slots_2026-10-19.md` §1.1). Only the id `49281` remains CLIENT-UNCONFIRMED — and the slot resolves its icon **by name** from the client's own spell data, so a wrong id cannot produce a wrong prompt. |
| S-17 Searing Totem — **live rule** | **CLOSED** | Same lane: slot 17, rule 9b (`st.shaman_guide.get_searing_upkeep_due`). |
| S-20 Call of the Elements — **live slot** | **CLOSABLE** | See U-10 and §7 BS-4. The id, the water slot and the clock reader are all sourced; the **APL rank** (where CoE sits in the Wrath priority order) is still owed by the CoE triage, and that is a *rule position*, not an id. |
| The `hud_show_lightningshield` / `hud_show_searing` **defaults** | **CLOSED** | The defaults have landed: `config_presets.lua:1064-1065` → `hud_show_lightningshield = false`, `hud_show_searing = false` (nil = off, so no default-visible change). |
| The `hud_show_lightningshield` / `hud_show_searing` **options widgets** | **CLOSED** | The **shaman-slot-options** lane landed them while this sweep was running: `option_tables.lua:5851-5852` (toggle + order 8.47 / 8.48 in the shaman section's shared `hud_rotation_widgets` builder), with the defaults at `config_presets.lua:1064-1065` (both `false`). See `bench/shaman_slot_options_2026-10-19.md` §1.1. **Both halves of the original filing are now closed.** |
| The two maintain mirrors in `ST.SHAMAN.HUD_TEMPLATES` | **STILL-FILED** | New filing (shaman-slot-options lane, "Filed for the orchestrator"): a template pick **writes** the slot keys, so a "Full Enhance" template that listed the two maintain mirrors would flip them **on** — a behaviour change beyond "wire the widget + the default". The mirrors stay `false` by default and the templates never listed them, so the current state is consistent. **What would close it:** an operator ruling on whether any template may enable a mirror (the templates' documented rule is that a pick writes the slot keys it lists). |
| S-29 Lightning Shield / Water Shield choice | **STILL-FILED** | The maintain only fires while **no** shield aura is up, so a Water-Shield build is never prompted after its first shield; the residue is a single spurious LS prompt before the player has cast their shield. **What would close it:** a mana input (the shaman has none today — the same gap as the paladin's mana-sustain row, P-22) or an explicit "which shield" read; the audit itself defers it ("the Shield choice needs mana awareness"). |
| S-18 Fire Elemental snapshot line-up | **STILL-FILED** | Two legs, both without a client source: (a) the "Wrath of Air" weapon-buff aura id — **no client source** (the id the filing quotes, 3738, has 0 hits across all four classic branches' `Interface/AddOns`); (b) a trinket-**stack** feed — the addon reads trinket *cooldowns* (`hud.lua:323`) but a trinket's proc count is not an item API. The weapon swap is also not portable under combat lockdown. |
| S-05 Flame Shock refresh on expiry | **CLOSABLE** | The sim finding is already in the tree, verbatim, at `config_presets.lua:1031-1035`: "every sim re-applies Flame Shock only when the dot is INACTIVE (SoD P6/P4, Era default, TBC default, Forever testing.build all use `not dotIsActive`; none refresh early), so the sim-exact value is 0". The **only** thing blocking it is the value `3` at `config_presets.lua:1047` plus the pin in `tests/shaman_guide_state.lua` (`:120`, `:1299`, `:1620`, `:1749-1752`). Build: §7 BS-4c. |
| S-11 Chain Lightning enemy count | **STILL-FILED** | **Sharper reason (now proven, not merely suspected):** no client API counts enemies and the shipped clients' FrameXML contains **no** Chain Lightning reference at all — grep for `ChainLightning` over `classic_era`, `classic_titan`, `classic_anniversary` and `origin/forever` returns 0 hits in every branch. So the sensor does not exist in the client, and no in-client probe can be written against a Blizzard contract. **What would close it:** a third-party ground truth (a combat-log unit-appear counter) plus a decision to accept a 0.5 s-lagged count — i.e. it needs an operator ruling, not a lookup. |
| S-15 Twist keyed on the imbue buff | **STILL-FILED** | The stamp model cannot see the imbue's **expiry** (the aura scan captures active-only), and the "GoA 25359" id has **no client source** (0 hits across the four classic branches). **What would close it:** a client-side "buff about to expire" source (none exists in the addon's read set — `api.scan_player_aura` returns remaining only for *active* rows) or a cited source for 25359. |
| S-23 Stormstrike cooldown per family | **CLOSABLE** | See U-09 and §7 BS-4b. |
| S-24 Autocast cooldowns | **STILL-FILED** | The HUD can show a **trinket** cooldown (`hud.lua:320-346`, `trinket_has_on_use`), but "autocast" for racials is a different surface (a racial's own cooldown on the player's own action bar) and the addon has no per-racial cooldown row on the shaman's HUD row. **What would close it:** a design decision on where an on-use racial's CD would live (HUD row vs the rotation label) plus a per-client racial id set — the same shape the trinket slots already use. |
| S-26 Twist rank (max-rank 25587 vs the downrank note) | **OPERATOR DECISION** (not research-closable) | The sim twists max rank and pauses at low mana; the module's note says downrank. This is an open ruling, not a missing source. Listed in §10. |
| S-27 Forever static totem maintain | **CLOSABLE (the ids) / STILL-FILED (the slot design)** | The ids are WEB-CONFIRMED in `bench/ids_research_2026-10-19.md` §2: `16387` Flametongue Totem (forever), `25361` Strength of Earth Totem (forever), `25570` Mana Spring Totem 20/2s (tbc), `10438` Searing Totem (forever). The **slot design** stays filed: three new guide slots vs reusing twist/magma, and the client source carries none of these ids (0 hits) — the in-client confirmation is still owed. |
| The shaman's namespace mirror (HU-7 stopgap) | **CLOSED (stopgap), central fix still owed** | `classes/shaman.lua` mirrors `st.SHAMAN = ST.SHAMAN`; the engine resolves via the AceAddon table first (`practice.lua:3305-3325` `addon_object()`), so the central fix has landed and the per-class mirror is a belt-and-braces no-op. The other five classes' mirrors should be confirmed by the orchestrator. |

### 4.2 Hunter (`bench/hunter_rotation_drills_2026-10-19.md` §4 + `bench/class_features_drills_2026-10-19.md` §2.3)

| Item | Verdict | Closing source / sharper reason |
|---|---|---|
| H-03 naked-Chimera guard | **CLOSED (the guard)** | The guard now withholds only when the sting is *known* down (`serpent_active == false`); an unknown debuff allows. |
| H-05 Lock and Load probe | **CLOSED** | The gather writes `inputs.lnl_ready` from the class's existing throttled aura probe. |
| H-04 Serpent Sting upkeep / the target-debuff read | **CLOSABLE** | See U-07 and §7 BS-3. |
| H-07 TBC Steady rank 34120 | **CLOSABLE** | See U-08. |
| H-10 TBC Arcane Shot 27019 (the arm is dormant behind `TBC_ARCANE_ENABLED = false`) | **STILL-FILED** | The id is sourced (`bench/ids_research_2026-10-19.md` §2 — 27019, TBC Arcane Shot); the blocker is **slot budget** ("the base set is full 6/6 and there is no arcane slot", `hunter_guide.lua:479`). **What would close it:** a slot-contract decision (raise the hunter's 6-slot cap, or demote a slot) — a design ruling, not a research item. |
| H-11 TBC mana group (Viper 34074 / Hawk 27044 / mana potion) | **CLOSED by ruling (CUT from the guide)** | `bench/hunter_open_2026-10-19.md` §2: "CUT from the guide engine … Build shape instead: HUD 'OOM → Viper' badge … + prepull checklist in the practice/report layer. No engine arm, no slot." The *badge* build is still open but is a shape, not evidence. |
| H-12 TBC melee weave (wait at melee 400 ms, buffer min(0.5 s, 25 % swing)) | **CLOSED by ruling (CUT)** | Same section — the stateless engine cannot express APL move/wait timing; parked under the melee-weave/move-cue follow-up. |
| H-13 TBC prepull (Hawk 27044 at −20 s; Steady at 0.5 s) | **CLOSED by ruling (CUT from the guide) / build in the practice layer** | Same section; the practice/report checklist shape is the agreed home. |
| H-14 Era upkeep (Serpent / Arcane / traps / Volley / Mongoose / Wing Clip) | **CLOSED by ruling (CUT)** | The Era set is aimed/raptor/multi only; the engine's guide arm was ruled out. |
| H-15 Era melee-weave movement tech | **CLOSED by ruling (CUT)** | Rule 7 only RIDE-surfaces an already-queued Raptor. |
| H-16 Wrath Black Arrow / Explosive Trap tier | **STILL-FILED** | The trap data now ships (63672 / 49067, 30 s each — SIM-CONFIRMED per wowsims/wotlk) and the trap machine tracks them, but the guide still never prompts a trap. **What would close it:** a guide slot (the Wrath set is full 6/6 — the same slot-budget ruling as H-10) **and** an APL-literal trap rule. |
| H-17 Readiness 23989 as a rotation event | **STILL-FILED** | The facts are in the tree (3 min CD, the reset list, the 10 s smart double-RF delay) and the practice layer uses the reset list; the **live guide arm** has no Readiness slot. **What would close it:** a guide slot + a rule that consumes the reset list (the reset itself is a cooldown event, not a shot priority). |
| H-18 Improved Steady Shot 53220 | **CLOSED (data) / closed by ruling (no engine arm)** | The id and the 12 s duration are exported and the window is visible in the HUD; no APL branches on it, so the guide must not either (`bench/hunter_open_2026-10-19.md` §1). |
| H-19 Sniper Training 53304 stationary buff | **STILL-FILED** | No stationary/movement input exists for the hunter (the addon's `api.IsPlayerMoving` covers the player, not a target-relative stance). It is a positioning aid, not a rotation. |
| H-20 / H-21 Forever SniperShot / Summon Hawk id tables | **STILL-FILED** | See U-06 / §6 U1. The tables ship empty by design (`classes/hunter.lua:137-146`). |
| H-22 Forever hawk count | **STILL-FILED** | See U-06. |
| H-23 Forever Multi-Shot 2643 | **STILL-FILED** | "the sharpest Forever conflict" — the sim's default APL prompts Multi 2643 but ships `Use Multi-Shot` inconsistently with the other flags. **What would close it:** an in-client answer on 1.60.x (which of the three default flags is real), not a sim re-read. |
| H-24 Forever HHA sequence (2× Hawk 1293527 + Arcane 14287) | **STILL-FILED** | Needs the hawk-count source (H-22) and a sequence state; blocked behind H-22. |
| H-25 Forever Sniper buff extends auto range | **STILL-FILED** | The bypass input `sniper_range_buff_active` is written nil (`classes/hunter.lua:2349`); it needs the Sniper-buff aura id from the H-20 table. |
| H-26 lust suppression | **CLOSED by operator ruling (CUT)** | `h2-cut` lane (journal rows 118/120): the lust branch is removed; the re-enable path is documented as a future opt-in. |
| H-27 TBC Arcane rank conflict (WA 14287 vs sim 27019) | **CLOSED** | Sim wins; 14287 stays out by design (`bench/hunter_wa_map_2026-10-19.md` §4). |
| H-28 Retail inert | **CLOSED** | `hunter_guide.lua` RETAIL short-circuit. |
| The `practice_rotation` consumer shape (new, hunter-drills lane) | **STILL-FILED (shared-engine)** | The hunter's table is a **per-family map** (`ST.HUNTER.PRACTICE_ROTATIONS[family]`) with `ST.HUNTER.practice_rotation` holding the running client's slice — the sibling lanes' flat `entry.family` filter does not apply there. The shared engine's rotation-table consumer does not exist yet (`bench/druid_drills_2026-10-19.md` §5 note 4). **What would close it:** the engine lane builds a consumer that accepts both shapes, or every class moves to one shape. |

### 4.3 Warrior (`bench/warrior_practice_2026-10-19.md` §2/§3)

| Item | Verdict | Closing source / sharper reason |
|---|---|---|
| W-06 Overpower stance gate | **CLOSED** | The stance is read from the client's own stance aura; the sim's ids are re-confirmed this session (§3 U-13). |
| W-08 Execute drains the rage pool | **CLOSED** | `st.warrior_guide.rage_after_execute(rage, cost, drains_all)`; the burn drill consumes it. |
| W-20 Devastate 25212 | **CLOSABLE (the figure) / STILL-FILED (the build)** | The figure is **corrected and sourced** — the audit's "rage > 60" comes from the tbc-new **fury** APL, the **arms** APL's Devastate line is `DW Arms` + the Delay Check + `currentRage >= 40`. The *build* stays filed for three concrete reasons: (a) Devastate sits **below** the Heroic Strike line in the same APL, so a rule above HS would prompt a spell the sim never prefers there; (b) its conditions need the 2H/DW read ("DW Arms" = Slam cast time > 0.5 s — **no reader in tree**); (c) a guide slot (the TBC set is at 7 of the 8 the contract allows) and a HUD mirror (the HUD row is pinned at 8 by `tests/hud_state.lua`). **What would close it:** a TBC-arms branch, a 2H/DW read, and one guide slot. **CORRECTED 2026-10-20** (desk `corpus-corrections`): the **id** in this row's title is wrong — **25212 is the TBC Hamstring, not Devastate** (`bench/rotation_gap_vs_apl_2026-10-20.md` §0.3; the tbc-new fury APL's i=19 casts 25212 = Hamstring — `bench/warrior_apl_utility_build_2026-10-20.md` §1). The *figure* above still stands; the Devastate row's own id is **not sourced in the corpus** (UNCONFIRMED — do not build on 25212 for it). |
| W-15 Forever Rend toggle | **CLOSABLE** | The rule exists and is dormant on Forever; what is missing is only the toggle + its options widget (the `option_tables.lua` / `config_presets.lua` pair). No evidence is in doubt. Build: §7 BS-7. |
| W-17 SoD stance-dance aura 426969 | **STILL-FILED** | No client source (0 hits across the four classic branches) and the sims do not model the SoD stance-dance. **What would close it:** an in-client `UnitAura` probe on a SoD warrior in the stance-dance state. |
| W-19 Victory Rush (Forever) | **CLOSED by operator ruling (SKIP)** | Operator SKIP (no Forever APL line; the sims never kill the target). The id question (U3) is therefore moot for this release. |
| W-21 Sunder/Rend/Hamstring **HUD mirror** | **CLOSABLE** | The guide slots already ship; the HUD row is the only gap, and the row count is a pin in `tests/hud_state.lua` (the HUD lane's file) — a pin update, not a research item. Build: §7 BS-8. |
| F-1 the warrior panel ran the **shared twist session** | **CLOSED** | `practice_ui.lua:944-953` — the warrior's own drill list is now `warrior_core_order`, `warrior_ww_delay`, `warrior_sunder_upkeep`, `warrior_execute_burn`. Pin: `tests/practice_ui_state.lua:4013`. |
| F-2 register the four drills + the `warrior_rotation` scenario in the shared registry | **CLOSED by the supersession design** | The engine reads the **class's** list (`H.practice_drills(class_key)` → `ST.<CLASS>.practice_drills`, `practice.lua:3484-3498`); the built-in registry entries are kept only as superseded shells (`practice.lua:3331-3336` `H.SUPERSEDED_DRILLS`). The class drills live in `classes/warrior.lua:3868+`. |
| F-3 the per-class practice map must change shape | **CLOSED (unnecessary)** | The map (`practice_ui.lua:913-953`) keeps a `mode` key, but that key now points at a **class-owned** drill for all six classes, which is the intent the filing wanted. |
| F-4 the HUD mirror for a Devastate slot | **STILL-FILED** | Part of W-20. |
| F-5 the Forever Rend toggle + the stance/threshold options | **CLOSABLE** | Same build as W-15 (§7 BS-7). |

### 4.4 Druid (`bench/druid_drills_2026-10-19.md` §2)

| Item | Verdict | Closing source / sharper reason |
|---|---|---|
| DU-13 FF omen-fishing | **CLOSED (class side) / STILL-FILED (the Omen-ICD assumption)** | The class now proves the Omen's ICD from the Clearcasting proc buff (16870). The remaining doubt is explicit and unchanged: "the assumption that the Omen's ICD and its proc buff share one window is UNCONFIRMED in-client". **What would close it:** one in-client observation (does a Clearcasting proc land exactly at the Omen's lockout end?). The failure mode is bounded (a fish spent at most one ICD early). |
| DU-22 W1 latency term | **CLOSED** | The gather now reads main.lua's raw world latency; the Wrath Tiger's Fury line includes the latency term. |
| DU-15 trick windows | **STILL-FILED** | The class-side inputs are wired; the **rules** live in `druid_guide.lua` and still need the live bite / shred costs — "neither spell has a rank table in this module, so a cost probe on them would read an unconfirmed id". **What would close it:** a rank table (or a client-resolved cost read) for Bite and Shred. |
| DU-16 powershift (the in-game SHIFT prompt) | **CLOSABLE (the Wolfshead half) / STILL-FILED (the Furor half)** | The Wolfshead half is now fully sourced (U-03 → §7 BS-2). The **Furor** half stays filed: "the Furor talent, whose id / tab / index has **no source** in this codebase (main.lua's `talent_positions` covers Wrath only), and a name probe (`GetSpellInfo("Furor")`) is not a knowledge proof — the client answers a name for any spell it ships". **What would close it:** a published Furor talent id + a talent read that is a *knowledge* proof (`GetTalentInfo` on a verified tab/index, or `C_SpecializationInfo` on a client that exposes it). |
| DU-18 Claw builder / DU-21 position input | **STILL-FILED** | No client API answers facing. The client source confirms the *shape* of the neighbours (`IsSpellUsable` answers usability, never facing) and no `CannotShredTarget` counterpart exists in any branch. Keep `can_shred` nil. |
| DU-11 Rake DPE check | **STILL-FILED** | Needs AP / DPE and proc inputs the class does not gather (the sim's `rakeDpeCheck` + the glyph extension). |
| DU-12 clipRoar glyph extension | **STILL-FILED** | Needs the Glyph-of-Shred / item-set inputs (the sim's `MinRoarOffset` 12/14/25/27/34 s + `RipLeeway` 4 s). The shipped cover-to-end clip stays. |
| DU-14 pooling as a cast-gate | **STILL-FILED** | Engine side (`pendingPool` → `floatingEnergy`); the class already exposes the tick phase. |
| DU-20 Faerie Fire manual maintain | **CLOSED (documented stance)** | Manual by stance is the documented policy; the Wrath/Forever Omen-fish rules are live (DU-13). |
| DU-23 TBC RipCP user-config | **CLOSED** | The `options-ripcp` lane shipped the widget + the default 4; the engine input and the gather are live. |
| DU-24 consumables / mana layer | **STILL-FILED** | No mana input and no guide slot for Tea / potion / Innervate. The druid's mana tier is the same gap as the paladin's P-22 and the hunter's H-11. |
| DU-25 bearweave / flowerweave / snekweave / powerbear | **STILL-FILED (documented cut)** | A bear timer / rage input does not exist; the scope cut stands. |
| The shipped `druid_powershift` entry's grade drift | **CLOSED** | `practice.lua:3335` → `druid_powershift = "druid_powershift_rework"` in `H.SUPERSEDED_DRILLS`, so the old entry's grading is delegated to the sim-faithful rule. |

### 4.5 Rogue (`bench/rogue_drills_rotation_2026-10-19.md` §2/§5)

| Item | Verdict | Closing source / sharper reason |
|---|---|---|
| R-01, R-02, R-04…R-10 | **CLOSED** | Slot-less actions ship; the audit's "7 slots, frozen" note is stale — the guide ships 11 (`tests/guide_contract.lua:1353`). |
| R-03 builder identity (Hemo excluded) | **CLOSABLE** | See U-04 — the name is "Hemorrhage" and the TBC id is **26864** (the bench's 26862 is Sinister Strike). Build: §7 BS-6. |
| R-11 Rupture per-CP durations | **STILL-FILED** | See U-05. |
| R-12 Thistle Tea (the Eureka-25 line) | **STILL-FILED** | The SoD 10/40 line is reachable (the SoD latch landed). The Eureka-25 line needs the in-client Eureka probe id `1259812` — **no client source** (the classic branches carry no such id) and no wowhead entry was recorded for it in `ids_research`. **What would close it:** a cited source for 1259812 (a TBC-era spell "Eureka"? — the id is the thing to prove) or the operator's in-client `GetSpellInfo`. **PARTLY CLOSED 2026-10-20** (desk `corpus-corrections`): the **name** is now settled — the rogue APL's own variable is "Gnome Eureka - Should Cast" and 1259812 = **"Gnome Eureka"** on the Forever client (`bench/rogue_apl_utility_build_2026-10-20.md` §3.7; `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **R8**). The **client** proof of the id is still owed, so the row stays filed. |
| R-16 Shiv EA-context check | **STILL-FILED** | Needs the APL-literal EA-window design: "the family's minimum-EA and Shiv-context windows are not modelled". The family gate, the Mutilate gate and the CP gate already ship. |
| R-18 SoD Envenom-primary (Poisoned Knife 425012, Vanish→Envenom, Cut to the Chase) | **CLOSABLE (the id) / STILL-FILED (the rest)** | `425012` is WEB-CONFIRMED: `bench/ids_research_2026-10-19.md` §2 (`https://www.wowhead.com/classic/spell=425012/poisoned-knife`, "Poisoned Knife (rune engraving)", SoD). The **Vanish→Envenom sequence** and **Cut to the Chase** remain filed: the sequence needs a slot/sequence state and Cut to the Chase has **no id in the APLs the lane touched** (the rogue lane's own §4 correction). |
| R-19 Wrath sin triad (CtC-anchored SnD refresh; Vanish→Overkill) | **CLOSABLE (the Hunger for Blood half — done) / STILL-FILED (the rest)** | The HfB upkeep shipped: `rogue_guide.lua` `HFB_FAMILIES` / `HFB_REFRESH_BY_FAMILY` / `hfb_verdict`, rule 1c, and the class resolves the buff **by name** ("Hunger for Blood") with no shipped id. The sim id is re-confirmed this session: `https://www.wowhead.com/wotlk/spell=51662` → **301** → `/wotlk/spell=51662/hunger-for-blood`, title "Hunger For Blood" (the rogue lane's citation is correct). The **CtC / Rupture-anchored SnD** rule needs the fight's remaining time, which the guide inputs do not carry (only the practice session has a fight clock). **Vanish→Overkill** needs a guide slot + prepull context; the sim id is re-confirmed (`26889` → `/vanish`). |
| R-20 Tricks / Killing Spree / **Venom** | **STILL-FILED** | The ids need a guide slot (the rogue's 11 are frozen by `tests/guide_contract.lua:1353`) plus APL-literal design. One id correction confirmed this session: `https://www.wowhead.com/wotlk/spell=57934` → **301** → `/wotlk/spell=57934/tricks-of-the-trade`, title "Tricks of the Trade" — the rogue lane's §4 correction is right (57934 is **Tricks**, not Cut to the Chase). **CORRECTED 2026-10-20** (desk `corpus-corrections`): the third id's **name** was wrong — 1310703 is **Venom** on the Forever client, not "Riposte" (`bench/rogue_apl_utility_build_2026-10-20.md` §3.8; `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **R7**). |
| R-21 Sweaty 0.5 s widening | **STILL-FILED** | The ≥ 79 energy override ships; the 0.5 s widening needs in-client proof. |
| R-22 Retail sim verification | **STILL-FILED** | No retail sim repo is in the brief set; the retail rows stay guide-sourced and UNCONFIRMED (the rotation's retail slice is empty). |
| §5.1 a twelfth guide slot for the Hunger for Blood upkeep | **STILL-FILED** | The guide slot contract is frozen; the upkeep rides the rotation label meanwhile. The HUD could carry it as an aura row (the same way it carries SnD) — that is a slot-free alternative and is the cheapest closure. |
| §5.7 the POOL verdict as an illegal cast | **CLOSED by the operator ruling (HU-8)** | The plan's Phase 3 rules: "A class may state a hold explicitly … Casting during a hold = **illegal cast → F**. Doing nothing during a hold = correct … A nil step with no hold statement stays **unknown** → no attempt, never a wrong grade." The engine therefore grows a hold concept, which is exactly what the filing asked for. |

### 4.6 Paladin (`bench/paladin_practice_contract_2026-10-19.md` §3/§4)

| Item | Verdict | Closing source / sharper reason |
|---|---|---|
| P-05 SoC scored 7 PPM, white hits only | **STILL-FILED** | The proc model (`twist.lua:64-70`) and the attempt detection (`twist.lua:103-110`) live in `twist.lua`, which the practice-contract lane did not own. **What would close it:** a `twist.lua` change — arm the twist attempt only on a *white* SoC proc and score it at 7 PPM — plus a `twist` suite pin. The evidence (7 PPM, white hits only) is the sim's and is not in doubt. |
| P-06 Twist on SoC rank 1 | **CLOSABLE (build)** | The engine half is live (`out.rank1_advice`, `nextaction.lua:851`; the live reader `classes/paladin.lua:3181`); only the **slot** (nextaction_ui) and the **option** (options lane) are missing. Build: §7 BS-5 / BS-7. |
| P-16 Judgement stopattack | **CLOSED (nothing to build)** | The engine advisory is live (`nextaction.lua:841`) and the frame renders STOP; the macro half cannot exist (an addon cannot cast). |
| P-17 Prepull the primary seal | **CLOSABLE (the pull-timer source)** | The engine half is live (`nextaction.lua:388` `PREPULL_SEAL_LEAD_SECONDS`, `:845` `out.prepull_ready`); the **pull-timer source** lives in `main.lua` (out of the contract lane's scope). The drill half is built. Build: §7 BS-8 (the shared main.lua pull clock). |
| P-22 TBC mana-sustain governor | **CLOSABLE (options)** | The read path is live (`classes/paladin.lua:3173-3177`, `nextaction.lua:549`); only the **value** (a widget + a default) is missing. Build: §7 BS-7. |
| P-24 Forever Echo of Command / Righteousness | **CLOSABLE** | The id tables are deliberately empty (`classes/paladin.lua:99-103`) "until GetSpellInfo confirms the ranks in-client" — but the ids are now WEB-CONFIRMED in `bench/ids_research_2026-10-19.md` §2: `1311703` Echo of Command (SoC chance), `1311704` Echo of Righteousness (forever pages). The class resolves by **name** through `api.get_spell_query`, so the name is the load-bearing fact and it is certain. Build: §7 BS-5. |
| P-25 Forever Holy Strike | **CLOSABLE** | See U-12 (10333). Build: §7 BS-5. |
| P-29 Wrath 2pc-T10 DS reset as DS readiness | **CLOSED (handled by design)** | "post-2pc DS resets surface as `ds_remaining` readiness, so the walk elevates DS automatically; the order is unchanged" (`nextaction.lua:900-903`). Explicit set-bonus detection is a nice-to-have that needs a set id + an equipment probe (out of offline-testable scope). |
| P-30 SoD strictSequence twist (wait the swing out) | **CLOSABLE (the render)** | The engine half is live (`nextaction.lua:854` `out.hard_wait`) and the provider feeds it (`classes/paladin.lua:3328`); only the **render** in `nextaction_ui.lua` is missing. Build: §7 BS-5. |
| U-11a SoD variants' in-client behaviour | **STILL-FILED (behaviour only)** | The ids are now web-confirmed (§3 U-11); the *behaviour* is the standing U-14 caveat. |
| U-11b the SoD variant **selection** in a practice session | **CLOSABLE (caller obligation)** | The live gather picks the variant from live build signals; a practice session carries none, so the mode defaults to Exodin unless the context names another (`ctx.fcfs_mode`). The contract already supports it — the closure is to have the session supply `ctx.fcfs_mode` for the SoD variant drills, and to pin that the default stays Exodin. |
| U-12 Forever Holy Strike id | **CLOSABLE** | See U-12. |
| U-14 every in-client behaviour of every number | **STILL-FILED (standing)** | Operator-owned. |
| U-15 every grading band | **CLOSED (policy)** | `[DESIGN]`. |
| U-16 the practice sim's mana model | **CLOSABLE (as a contract)** | The shipped sim has **no** mana clock; the scenario runs a mana budget instead, and the fillers are gated on `resources.mana_pct`, so a session that does not supply one never prompts a filler (the safe direction). The closure is: the scenario must publish a mana budget, and the three drills that need it must say so. The *budget* itself is an addon model and must be labelled as one. |

---

## 5. Table D — `bench/ids_research_2026-10-19.md` (the id ledger re-checked)

The ledger's 43 CONFIRMED rows stand. The 17 UNCONFIRMED rows (U1–U17) re-checked:

| # | Item | Verdict | Closing source / sharper reason |
|---|---|---|---|
| U1 | Forever rank tables (1310785/86, 1293525/26/27, 1293248, 1312639) | **STILL-FILED (operator)** | **The client source does not carry them:** grep over `origin/forever:Interface/AddOns` returns 0 hits for each of 1310687, 1293241, 1293525, 1293526, 1293527, 1293248, 1312639, 1310703, 10333, 1311703, 1311704, 11281, 11294, 6774, 11275, 11300, 7676, 13877, 14177, 1241584. So there is no offline client source and the closure is the operator's 1.60.x `GetSpellInfo`. **NAMES SETTLED 2026-10-20** (desk `corpus-corrections`): two of those ids are now **named** by the Forever spell data — 1310703 = **Venom**, 1241584 = **Mutilate rank 4** (`bench/rogue_apl_utility_build_2026-10-20.md` §3.3/§3.8) — but the *client* source is still absent, so the row stays filed. |
| U2 | hawk-count source | **STILL-FILED** | See §3 U-06. No client contract; the sim *constructs* the hawks. |
| U3 | Victory Rush on Forever | **CLOSED by decision for this release** | The operator SKIPped Victory Rush (journal: "Victory Rush = SKIP (already inert-by-default; HOLD DORMANT stands)"), so the Forever VR id/duration question does not gate the release. Keep the id question filed for a future VR lane. |
| U4 | TBC shaman Flame Shock fight ≥ 12 s gate | **CLOSABLE (the source is now found; the semantics narrowed)** | The TBC enhancement APL is at `https://raw.githubusercontent.com/wowsims/tbc-new/master/ui/specs/shaman/enhancement/apls/default.apl.json` (fetched this session, 1321 B). Its Flame Shock line is `{"auraIsInactive":{"sourceUnit":{"type":"CurrentTarget"},"auraId":{"spellId":25457,"tag":1,"rank":7},"includeReactionTime":true}}` together with `{"cmp":{"op":"OpGe","lhs":{"remainingTime":{}},"rhs":{"const":{"val":"12s"}}}}`, and the file contains **no** `currentTime` comparison. So: the 12 s threshold is real and sourced, and it is **not** a fight-elapsed gate — it is a *remaining-time* comparison on the same line. The filing's "fight ≥ 12 s" reading is therefore not what the APL says. **The remaining question is the APL's `remainingTime` semantics**, not the source. |
| U5 | SoD p4-twist path (404 was a wrong guess) | **CLOSABLE** | The correct path is `https://raw.githubusercontent.com/wowsims/sod/master/ui/retribution_paladin/apls/p4-twist.apl.json` — **fetched this session, HTTP 200, 615 bytes**. The `ui/paladin/apls` guess 404s; the class dir is `ui/retribution_paladin/apls/`. The fetched p4-twist APL confirms the p4 shape (prepull Seal of Martyrdom 407798 at −1.5 s + Seal of Command 20920 r5 at 0; the 200 ms strict-sequence twist windows; the 10 % `remainingTimePercent` rule; the 429152 rune gate). The p8 line's independent 10 % rule is unaffected. |
| U6 | SoD Stormstrike 6 s CD trigger (rune vs base) | **CLOSABLE (the shipped value) / STILL-FILED (the mechanism)** | The shipped value 6 s is operator-confirmed in-client and the sim models it flatly; the *mechanism* (does the rune grant the 6 s, or is it base?) does not change any shipped number. Build: §7 BS-4b. |
| U7 | in-client feel of every row | **STILL-FILED (standing)** | Operator-owned. |
| U8 | Bloodthirst Forever (name-only by design) | **CLOSED (design)** | The name-vs-id rule (name on TBC, id elsewhere) means the Forever Bloodthirst resolves by name; no id table is needed. |
| U9 | Forever bonus kit (14287/25295/14325/25296/14266/14268/1317257/469145/3045/5384/2643/20904/14271/20572) | **CLOSABLE (4 of 14) / STILL-FILED (the rest)** | **Client-sourced (origin/forever):** `20572` = Blood Fury (Orc racial) — `origin/forever:Interface/AddOns/Blizzard_CooldownBroadcaster/TrackedCooldowns.lua:450` (`Orc = 20572, -- Blood Fury`); `13750` = Adrenaline Rush — same file `:252`; `14266` = Charge (Warrior racial) — `origin/forever:Interface/AddOns/Blizzard_BoostTutorial/Blizzard_TutorialRacialData.lua:486`; `5384` = Feign Death — `origin/forever:Interface/AddOns/Blizzard_NewPlayerExperience/Blizzard_TutorialData.lua:70`. **The other ten have no client source** (0 hits). **Correction:** `14287` appears in the client only as an *achievement* id (`Blizzard_TutorialManager.lua:4` `TutorialManager.NPE_AchievementID = 14287`) — it is not the Arcane Shot spell id; the bench's list must not be read as "14287 is a spell". |
| U10 | Rogue per-client ids | **CLOSABLE (the TBC set) / STILL-FILED (the rest)** | The TBC rogue set is now name-confirmed by wowhead's own redirect slugs (observed this session): **26862 = Sinister Strike**, **26863 = Backstab**, **26864 = Hemorrhage**, **26865 = Eviscerate**, **26867 = Rupture**, **34413 = Mutilate**, **26889 = Vanish**, **16511 = Hemorrhage** (both the /classic/ and /tbc/ slugs). The Wrath, Era, SoD and Forever subsets remain SIM-CONFIRMED-only. **The bench's SS/Hemo pairing is swapped — see §9-N1.** **CORRECTED 2026-10-20** (desk `corpus-corrections`): the swap is now **fixed in the three corpus places §9-N1 named** (`bench/class_features_drills_2026-10-19.md` R-03, `bench/rogue_rotation_audit_2026-10-19.md` §1, `bench/ids_research_2026-10-19.md` U10), and the rogue APL build lane's sim-sourced TBC table agrees (`hemorrhage` 26864 / `backstab` 26863 / `mutilate` 34413 — `bench/rogue_apl_utility_build_2026-10-20.md` §1.1 rows 34-36). The **Forever** subset's names are now settled too — 1310703 = **Venom**, 1241584 = **Mutilate r4**, 14183 = **Premeditation**, 1857 = **Vanish r2** (TBC/Forever), 1259799 = "Elune's Light", 1259812 = "Gnome Eureka", 14278 = **Ghostly Strike** (`bench/rogue_apl_utility_build_2026-10-20.md` §3) — the *client* proof is still owed. |
| U11 | Paladin per-client ids | **CLOSABLE (the SoD set) / STILL-FILED (behaviour)** | The SoD paladin aura/rune ids are web-confirmed with page titles (§3 U-11). The behaviour remains U-14. |
| U12 | Shaman per-client ids | **STILL-FILED (SIM-only) / CLOSED (the CoE id)** | SS 17364 is confirmed; the rune set (440580/408490/408507/425339/408498/408505/425336) is SIM-only; **66842 is now client-sourced** (§3 U-10). |
| U13 | Warrior per-client ids | **STILL-FILED (SIM-only) / CLOSED (the stance ids)** | 412507 is operator-confirmed in-client; the stance aura ids are SIM-confirmed and re-fetched this session (§3 U-13). |
| U14 | Druid per-client ids | **CLOSABLE (8345) / STILL-FILED (the rest)** | 8345's read path is now closed end-to-end (§3 U-03). Berserk 50334 (WotLK) is already CONFIRMED and shipped — `bench/buildout_druid_2026-10-17.md:138` ("Berserk: 50334 (WotLK, CONFIRMED …)"), `bench/class_features_drills_2026-10-19.md` DU-02 (rule W2) — so only the *client* confirm remains. |
| U15 | ISS mechanics | **STILL-FILED** | The page confirms the 12 s buff; the +15 % dmg / −20 % cost / consumed-on-cast numbers are SIM-side only. |
| U16 | H2 lust-suppression | **CLOSED by operator ruling (CUT)** | `h2-cut` lane; re-enable documented as a future opt-in. |
| U17 | 60052 R3 | **CLOSABLE** | `https://www.wowhead.com/wotlk/spell=60052` → **301** → `/wotlk/spell=60052/explosive-shot`, title "Explosive Shot". The page exists and the name matches the sim's Explosive Shot R3. |
| **N1** | *(new)* the bench's TBC rogue SS/Hemo pairing | **CORRECTION** | 26862 = Sinister Strike, 26864 = Hemorrhage (wowhead redirect slug + title, observed this session). The corpus has them swapped in three places — §9-N1. |

---

## 6. Table E — `bench/live_test_script_2026-10-19.md` §8 (U1–U17): which are closable OFFLINE

| # | Operator row | Offline-closable? | What changed in this sweep |
|---|---|---|---|
| U1 | Forever ranks/triggers | **No** | The client's FrameXML carries none of them (§5 U1) — the operator's 1.60.x `GetSpellInfo` is the only closure. |
| U2 | hawk-count source | **No** | No client contract exists (§3 U-06). |
| U3 | VR / Victorious | **Moot for this release** | Operator SKIPped VR; the id question is deferred, not closed. |
| U4 | TBC FS fight ≥ 12 s gate | **YES — the source is now cited** | The TBC enhancement APL is fetched and quoted (§5 U4): the 12 s threshold exists, and it is a *remaining-time* comparison, not a fight-elapsed gate. The operator still records the in-client FS behaviour, but the audit no longer has a missing source. |
| U5 | SoD p4-twist path | **YES** | The correct path is fetched and 200-OK (§5 U5). |
| U6 | SoD SS 6 s trigger | **Partly** | The shipped value is closed (operator-confirmed + sim); the rune-vs-base mechanism stays in-client. |
| U7 | feel of every row | **No** | Standing caveat. |
| U8 | Bloodthirst Forever | **YES (by design)** | The name-resolution rule makes the id unnecessary. |
| U9 | Forever bonus kit | **Partly — 4 of 14** | 20572 / 13750 / 14266 / 5384 are now client-sourced (§5 U9). |
| U10 | rogue per-client set | **Partly — the TBC set** | The TBC names/ids are now web-confirmed, and the SS/Hemo swap is corrected (§5 U10, §9-N1). |
| U11 | paladin per-client | **Partly — the SoD set** | The SoD aura/rune ids are web-confirmed with page titles (§3 U-11). |
| U12 | shaman per-client | **Partly — the CoE id** | 66842 is client-sourced (§3 U-10). |
| U13 | warrior per-client | **Partly — the stance ids** | 2457 / 71 / 2458 are sim-confirmed and re-fetched (§3 U-13). |
| U14 | druid per-client | **Partly — 8345** | The read path is closed end-to-end (§3 U-03). |
| U15 | ISS mechanics | **No** | SIM-side numbers. |
| U16 | H2 lust-suppression | **YES** | Closed by the operator ruling (CUT). |
| U17 | 60052 R3 | **YES** | The page exists with the matching name (§5 U17). |

**Net (17 rows):** **5 fully offline-closable** (U4, U5, U8, U16, U17), **7 partly** (U6, U9,
U10, U11, U12, U13, U14 — each has a named subset now cited and a named subset still owed), **4
operator-owned** (U1, U2, U7, U15) and **1 moot for this release** (U3, the operator's VR SKIP).
The operator's script needs no structural change; the "source of doubt" column for U4, U5, U9,
U10, U12, U13, U14, U17 can be updated with the citations in this file (that edit is the Phase-8
documentation pass, not this desk's scope).

---

## 7. Build specs — the CLOSABLE items, grouped into disjoint lanes

**Ownership rule:** one lane per class/file. A lane touches only the files it names; the shared
suites (`tests/guide_contract.lua`, `tests/hud_state.lua`) are edited **only** in that file's own
per-class section, append-only. No two lanes own the same file. No lane changes a default
without an explicit gate; every new toggle is nil-safe (`== false` hides, nil = off) and is
documented in the options pass. No lane invents an id or a number — each cites the source named
in §3/§4/§5.

**Contention note (important for sequencing).** While this sweep ran, four lanes landed and
touched the very files some build specs name: the **f10-shared-guard** lane (`guard.lua`,
`bars.lua`, `hud.lua`, `nextaction_ui.lua`, `rotationtext.lua`, `practice_ui.lua`, all 7 TOCs),
the **shaman-slot-options** lane (`option_tables.lua`, `config_presets.lua`,
`tests/options_load_state.lua`), the **hunter-drills** lane (`classes/hunter.lua`,
`hunter_guide.lua`, `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`) and the
**rogue/druid drills** lanes. The specs below were written against the tree as of this desk's
read; the orchestrator must re-read the cited anchors before dispatching, and must **not** run
two lanes on the same file at the same time. In particular:
`config_presets.lua` (BS-4c **or** BS-7, not both), `option_tables.lua` (BS-7 only),
`classes/hunter.lua` (BS-3 — the hunter-drills lane has just finished there),
`classes/shaman.lua` (BS-4 — the shaman lanes have just finished there), and the shared suites
`tests/guide_contract.lua` / `tests/hud_state.lua` (per-class sections only, and only after the
lanes that grow those sections have landed).

---

### BS-1 — compat probe lane (owns `compat.lua`, `tests/smoke.lua`)

**File:** `compat.lua`
**Exact change:** add two probe helpers next to their templates, in the same house style.

1. `api.scan_unit_aura(unit, predicate)` — a literal generalisation of `api.scan_player_aura`
   (`compat.lua:514-543`): same 40-row cap, same "no early break" rule, same
   `api.get_time()` axis, same whole-entry secret degrade (the wrapper at `compat.lua:456-488`
   already returns nil for a restricted row). The only changes are the `unit` argument and the
   default filter (`"HARMFUL"` for a debuff scan, `"HELPFUL"` for a buff scan). Contract to
   document: returns `nil, nil` when not found / when no aura API exists / when the predicate is
   not a function; callers must read nil as "unknown", never as "absent".
2. `api.is_item_equipped(item_id)` — reads the equipped item id through the **existing**
   `api.GetInventoryItemID` (`compat.lua:986`) over the equipment slot range
   `INVSLOT_FIRST_EQUIPPED..INVSLOT_LAST_EQUIPPED` (the client defines both; the values are
   1..19 on all four classic-line branches and on Forever — `Constants.lua`). Returns `true`
   only on an exact id match, `false` when the read is readable and no slot matches, and **nil**
   when the read is unavailable/secret (unknown ≠ false). Use the `INVSLOT_*` globals via
   `rawget(_G, …)` (the addon's undefined-global discipline) so a client without them reports nil.

**Pin:** `tests/smoke.lua` — (a) `api.scan_unit_aura("target", pred)` returns the match on a
stubbed `UnitAura` and `nil, nil` for a non-match and for a nil-unit read; (b) a **secret** row
degrades to "not found", not to a truncated match (the R2 rule); (c) `api.is_item_equipped(8345)`
is true for a stubbed head slot, false for a different id, and **nil** when `GetInventoryItemID`
is absent.

**Lane:** `compat-probes` (new). **Depends on:** nothing (it is the enabler for BS-2 and BS-3).

---

### BS-2 — druid Wolfshead probe (owns `classes/druid.lua`, `druid_guide.lua`, `tests/druid_state.lua`, `tests/druid_guide_state.lua`)

**File:** `classes/druid.lua` (gather) + `druid_guide.lua` (engine input spec)
**Exact change:** replace the "no honest probe exists" comment at `classes/druid.lua:1871-1878`
with the real, sourced position and add one input:
`inputs.wolfshead_equipped = api.is_item_equipped(8345) or nil` (nil = unknown, never false on
an unread client). The sim's check is `HasItemEquipped(8345)` in the tbc-new feralcat rotation
(`bench/class_features_drills_2026-10-19.md` §2.5), and the id is the wowhead-confirmed
Wolfshead Helm. **Do not** re-enable the SHIFT rule on this input alone: the Furor refund basis is
still unproven (§4 DU-16), so the input is a **reserved plug-in point** exactly like
`can_powershift` is today — the wiring is nil-safe and the rule does not read it until Furor is
proven. Update the `druid_guide.lua:184-186` comment accordingly.

**Pin:** `tests/druid_state.lua` — the gather writes `wolfshead_equipped == true` for a stubbed
equipped 8345, `false` for a readable non-match, and `nil` when the read is unavailable; the
engine's rule matrix does **not** change (the input is not consumed). `tests/druid_guide_state.lua`
— the input is not read by any rule (a "no rule consumes it" pin, the same shape as the
`can_powershift` reservation).

**Lane:** `druid-wolfshead` (new, druid-only). **Depends on:** BS-1.

---

### BS-3 — hunter Serpent target-debuff feed (owns `classes/hunter.lua`, `hunter_guide.lua`, `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`)

**File:** `classes/hunter.lua:2348` + `hunter_guide.lua` (the Serpent guard's input contract)
**Exact change:** `inputs.serpent_active` stops being the hard-coded `nil` and becomes
`api.scan_unit_aura("target", serpent_predicate)` → `true` (the sting is up on the target),
`false` (the scan ran and the sting is not up) or `nil` (unknown). The predicate matches the
**already sourced** ranks (13554 / 25295 / 49001 — SIM-CONFIRMED per the SoD p7 APL, the Forever
APL and wowsims/wotlk `serpent_sting.go`) **by name first and id second**, because the TBC
Anniversary client resolves by name. The existing guard semantics do not change: the Chimera is
withheld **only** when the sting is known to be down; an unknown debuff still allows.

**Pin:** `tests/hunter_state.lua` — (a) the target scan's true/false/nil land in
`inputs.serpent_active`; (b) a secret debuff row reads as unknown, not as "down"; (c) the
**unknown-hides** direction: with `serpent_active == nil` the Chimera prompt still fires.
`tests/hunter_guide_state.lua` — the naked-Chimera guard still withholds on `false` and allows on
`nil` (the three-state pin the lane already owns).

**Lane:** `hunter-serpent` (new, hunter-only). **Depends on:** BS-1.

---

### BS-4 — shaman CoE slot + FS default + Stormstrike duration (owns `classes/shaman.lua`, `shaman_guide.lua`, `tests/shaman_state.lua`, `tests/shaman_guide_state.lua`, the **shaman section only** of `tests/guide_contract.lua` and `tests/hud_state.lua`)

This is the largest closure. Three sub-changes, one lane, one class.

**4a — the water-totem clock (S-20 / U-10).**
*File:* `classes/shaman.lua`.
*Exact change:* add `local WEAVE_TOTEM_WATER_SLOT = 3` next to the existing
`WEAVE_TOTEM_FIRE_SLOT = 1` (`classes/shaman.lua:234`) and `WEAVE_TOTEM_AIR_SLOT = 4`
(`:175`), and a `refresh_water_from_totems` reader in the **fire-slot reader's shape**
(`classes/shaman.lua:989-1030`): `api.GetTotemInfo(WEAVE_TOTEM_WATER_SLOT)` already returns
`have_totem, name, start_time, duration, icon, mod_rate, spell_id` (`compat.lua:1076-1094`), and
`start_time` is on the `api.get_time()` axis, so the remaining time is
`duration - (now - start_time)`. Write `inputs.water_remaining` / `inputs.water_duration`.
Then add the guide slot `{ key = "coe", spell_id = 66842 }` (18th slot) and a rule **above Magma**
per the Wrath APL spine, gated on `st.family == "WRATH"` and on the water totem being under 20 s.
The id 66842 is **client-sourced** (`classic_titan:…/Classic/Constants.lua:300-304` lists it in
the client's own `TOTEM_MULTI_CAST_SUMMON_SPELLS`) and the slot number 3 is client-sourced
(`:288` `WATER_TOTEM_SLOT = 3;`).
**The APL rank of CoE is still owed** (the CoE triage) — until it is, the rule must be filed as
"rank provisional" in the code comment, exactly as the existing CoE rotation line already is
(`classes/shaman.lua:4012`).
*Pin:* `tests/shaman_state.lua` — the water reader returns the remaining/duration on the
`api.get_time()` axis, `nil` when the slot is empty/unreadable, and `nil` on a secret read;
the gather publishes `inputs.water_remaining` / `inputs.water_duration`. `tests/shaman_state.lua`
(shaman section of `tests/guide_contract.lua`) — the slot count becomes **18** and the frame
builds 18 icons (`tests/guide_contract.lua:1514-1515`); the HUD row becomes **11**
(`:1550`). Unknown-hides: with an unknown water read the CoE rule never fires.

**4b — the per-family Stormstrike duration (S-23 / U-09).**
*File:* `classes/shaman.lua` (the guide slot descriptor at `:2675-2676` and the HUD slot
descriptor near `:3328`).
*Exact change:* replace the static `swipe_duration = 10` with the per-family value
(Era 20 / SoD 6 / TBC 10 / Wrath 8), selected by `st.family`, and make the guide's `full`
prefer the **gathered** duration (which already exists: `classes/shaman.lua:2923-2924` writes
`inputs.stormstrike_duration` from the live `get_guide_cooldown` read) over the static fallback
(`nextaction_ui.lua:628` already does `inputs[sf.duration_key] or sf.slot.swipe_duration` — the
gap is that the **fallback** is wrong per family, not that the value is dropped).
*Pin:* `tests/shaman_state.lua` — the per-family fallback table; the SoD value is 6 (the
operator-confirmed number, central journal); `tests/hud_state.lua` (shaman census) — the HUD
mirror's fallback matches the same table. **No change to `nextaction_ui.lua`** (it is a shared
file — the shaman lane must not touch it; see the note below).

**4c — the Flame Shock refresh default (S-05).**
*File:* `config_presets.lua:1047`.
*Exact change:* `guide_flameshock_refresh = 3` → `0`, with the comment block at
`config_presets.lua:1031-1040` rewritten to state that the sim-exact value is 0 and that the
`3` was kept only because of the out-of-scope pin. **This edit is one line in a file the options
lane also owns — sequence it after BS-7, or hand it to the options lane, to avoid two writers.**
*Pin:* `tests/shaman_guide_state.lua:120,1299,1620,1749-1752` — the gather's default threshold
becomes 0; the "refresh at ≤ 3 s" pin becomes "refresh on expiry"; the explicit-override pin
(6) still works.

**Lane:** `shaman-coe-fs-ss` (new, shaman-only). **Depends on:** BS-7 for 4c (shared file).

---

### BS-5 — paladin Echo / Holy Strike / hard-wait render (owns `classes/paladin.lua`, `nextaction.lua`, `nextaction_ui.lua`, `tests/paladin_state.lua`, the **paladin section only** of `tests/guide_contract.lua`)

**File:** `classes/paladin.lua:99-103` + `nextaction_ui.lua`
**Exact change:**
1. Fill the two deliberately-empty Forever id tables with the **web-confirmed** ids
   (`1311703` Echo of Command, `1311704` Echo of Righteousness — `bench/ids_research_2026-10-19.md`
   §2) **and** keep the class's name-resolution path as the primary key so a wrong id cannot
   produce a wrong prompt (the class already resolves by name through `api.get_spell_query`).
   Rewrite the "deliberately EMPTY until GetSpellInfo confirms" comment to state the new
   standing: *web-confirmed, client-unconfirmed, name-resolved*.
2. Add the Forever **Holy Strike** id (`10333`) to the same discipline (the key already exists —
   `nextaction.lua:127` documents the discipline, only the id was missing).
3. Render the SoD strictSequence **hard wait**: the engine already publishes `out.hard_wait`
   (`nextaction.lua:854`) and the provider feeds it (`classes/paladin.lua:3328`); the frame must
   show it in the guide's HOLD/RIDE overlay (`nextaction_ui.lua:380-399` owns the overlay
   frame).

**Pin:** `tests/paladin_state.lua` — the echo id tables are non-empty and a wrong id still
degrades to unknown (never a wrong prompt); the Holy Strike id resolves. `tests/guide_contract.lua`
(paladin section) — the hard-wait render lights the HOLD overlay; the paladin slot count stays
**10** (`tests/guide_contract.lua:689,956`).

**Lane:** `paladin-forever-ids` (new, paladin-only). **Depends on:** none.

---

### BS-6 — rogue Hemorrhage builder (owns `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua`, `tests/rogue_guide_state.lua`)

**File:** `classes/rogue.lua:246-254`
**Exact change:** the builder candidate chain becomes
`{ "Saber Slash", "Mutilate", "Hemorrhage" }` (plus the existing dagger-mainhand `Backstab` and
the `GUIDE_SPELL_NAMES.builder` fallback), with a **family gate**: Hemorrhage is a TBC (and
Forever/Era) builder, not a SoD rune builder, so it must sit *after* the rune candidates and
*before* the generic Sinister Strike fallback — never ahead of a rune the sim prefers. The
English name is now certain ("Hemorrhage"); the TBC id is **26864** (not 26862) and the
Forever/Era id is 16511, both web-confirmed by wowhead's own redirect slug. Rewrite the
"Hemo-Ghostly is deliberately excluded (uncertain which rank the TBC sim gates)" comment.

**Pin:** `tests/rogue_state.lua` — the builder resolves to Hemorrhage when Mutilate/Saber are
unknown and the player is dagger-less (or whatever the chain shape decides) and the name
resolves; a **wrong/unknown** name resolves to nil and the chain falls through (unknown-hides,
never a wrong builder); the family gate pins that SoD never picks Hemorrhage over a rune.
`tests/rogue_guide_state.lua` — the guide's builder slot id follows the winner.

**Lane:** `rogue-hemorrhage` (new, rogue-only). **Depends on:** none.

---

### BS-7 — options pass: the missing widgets + defaults (owns `option_tables.lua`, `config_presets.lua`)

**File:** `option_tables.lua` (+ `config_presets.lua` where a new key needs a default)
**Exact change (three items, all nil-safe, no default-visible change):**

1. ~~The LS / Searing widgets~~ — **DONE, drop this item.** The shaman-slot-options lane
   already shipped them (`option_tables.lua:5851-5852`).
2. The **Forever Rend toggle** (W-15) — the rule exists and is dormant on Forever; add the
   toggle + its widget, defaulting to off (nil-safe), and the default must be documented in
   `config_presets.lua`.
3. The **TBC mana-sustain threshold** (P-22) — the read path is live
   (`classes/paladin.lua:3173-3177`, `nextaction.lua:549`); add the widget + a default.
4. The **Shaman Flame Shock refresh default 3 → 0** (BS-4c) — if this lane takes the shared
   `config_presets.lua` write, it must also flip the `tests/shaman_guide_state.lua` pins, or
   BS-4 must take the file. **One writer per file: pick one.**

**Pin:** `tests/options_load_state.lua` (the options suite) — every new
widget reads `db == false` → hidden, nil → off; a fresh profile shows no new visible control
unless its default says otherwise.

**Lane:** `options-pass` (new, options-only).

---

### BS-8 — shared-engine lane (owns `practice.lua`, `practice_ui.lua`, `main.lua`, `diag.lua`, `practice_stats.lua`, `practice_progress.lua`, `tests/practice_state.lua`, `tests/practice_ui_state.lua`, `tests/main_init_state.lua`, `tests/diag_state.lua`)

**File / exact change (three small items, one lane, no class files):**

1. **JE-1 — the paladin's `LCD.Register` degrade must be visible.** The paladin is a *class*
   file, so the counter's writer is a one-line class-side addition; to keep the lane disjoint,
   the **counter lives in `main.lua`'s runtime-diag line** and the paladin lane adds the
   increment. **Recommended split:** BS-8 owns `main.lua` (the diag line, in the same shape as
   `main.lua:1804-1808` `hud_cleu_register_errors=N`) and the paladin lane owns the increment
   in `classes/paladin.lua`. If the orchestrator prefers one lane, this lane may own both, but
   then it must not be run in parallel with BS-5.
2. **P-17 — the pull-timer source.** `main.lua` publishes the pull clock that
   `nextaction.lua:388/845` (`PREPULL_SEAL_LEAD_SECONDS`, `out.prepull_ready`) needs. The
   practice session already has a synthetic pull clock; the live guide needs the real one.
3. **F-13 — the O(n²) trim.** **Not part of this lane's build.** It stays filed (§2) until the
   per-site caps are cited.

**Pin:** `tests/main_init_state.lua` — the runtime-diag line shows the new counter; the
paladin's register failure increments it. `tests/practice_ui_state.lua` — the pull clock
publishes a timestamp the prepull rule can read.

**Lane:** `shared-engine` (new). **Depends on:** none (it does not touch class files).

---

### BS-9 — warrior HUD mirror (owns `classes/warrior.lua`, `warrior_guide.lua`, `tests/warrior_state.lua`, `tests/warrior_guide_state.lua`, the **warrior census only** of `tests/hud_state.lua`)

**File:** `classes/warrior.lua` (the `ST.WARRIOR.HUD_SLOTS` table) + `tests/hud_state.lua`
**Exact change:** add the Sunder / Rend / Hamstring mirrors to the warrior's HUD row. The guide
slots already ship; only the HUD row is missing, and the row's width is a pin in
`tests/hud_state.lua` (the HUD lane's file) — so the pin must move with the row. Sunder/Rend
are maintenance actions with no cooldown to ride → they ride the same "display-only, no swipe"
shape as the druid Claw mirror and the shaman's two maintain mirrors
(`bench/shaman_slots_2026-10-19.md` §1.3): hidden unless a `hud_show_*` toggle reads exactly
true.

**Pin:** `tests/hud_state.lua` (warrior census) — the row's width grows by the three slots and
the geometry pin follows; `tests/warrior_state.lua` — the mirrors are provider-hidden by
default (no default-visible change).

**Lane:** `warrior-hud-mirror` (new, warrior-only). **Depends on:** BS-7 (the new
`hud_show_*` defaults, if the toggles are new keys — if they are, the defaults land in
`config_presets.lua`, which BS-7 owns; sequence BS-7 before BS-9, or let BS-9 own only
`classes/warrior.lua` + the HUD pin and BS-7 own the config).

---

## 8. The still-filed register (sharper, testable reasons)

Every row below names **exactly what is missing** and **what evidence would close it**. Nothing
here is research-closable in this wave.

| # | Item | What is specifically missing | Evidence that would close it |
|---|---|---|---|
| F13 | The O(n²) `table.remove(list, 1)` trim (10 sites) | the per-site cap constants and the worst-case cost per event | cite each cap + convert the 4 combat-path sites to an index-offset ring (or a measured cost) |
| JE-1 | The paladin's `LCD.Register` degrade is invisible to `/st diag` | a counter and a diag line | BS-8 item 1 (the counter + `main.lua` line) |
| U-01 | Warrior rage regen | a source for the client's rage regen — **no wowsims model has one** | an in-client `UnitPower("player", 1)` delta over 1 s, or a cited non-sim source; until then the 10/s stays labelled an addon model |
| U-02 (refund) | The 40-energy Furor refund | a published Furor talent id + a *knowledge* proof | a talent id + `GetTalentInfo` on a verified tab/index, or `C_SpecializationInfo` where it exists |
| U-05 / R-11 | The 2–4 CP Rupture rows + the `min_ttd` split | the sim's per-CP durations **and** a decision to separate `min_ttd` from the dump rule | the wowsims rogue `rupture.go` rows per family + an engine split |
| U-06 / H-22 | The Forever hawk count | an observational count source | a probe that answers: the number of "Summon Hawk" auras on the player, or guardian-pet enumeration, or a combat-log summon count |
| U-11a / U-14 | The in-client behaviour of every confirmed number | an in-client observation | the operator's session (the ids are no longer the blocker) |
| S-11 | The Chain Lightning enemy count | a client-side enemy counter — **the client FrameXML has no Chain Lightning code at all** | an operator ruling to accept a third-party / combat-log count, or a documented cut |
| S-15 | The twist keyed on the imbue buff | a "buff about to expire" source; the GoA id 25359 has no client source | a client-side expiry read, or a cited source for 25359 |
| S-18 | The Fire Elemental line-up | (a) the Wrath-of-Air aura id (no client source); (b) a trinket **stack** feed (no item API) | an in-client `UnitAura` probe name + a trinket proc-count read |
| S-24 | The autocast cooldowns | a decision on where a racial's CD lives + a per-client racial id set | the HUD-row / rotation-label decision + the id set |
| S-27 (design) | The Forever static totem maintain | the slot design (3 new slots vs reusing twist/magma) + the in-client confirm of 16387/25361/25570/10438 | a slot-budget ruling + the operator's 1.60.x `GetSpellInfo` |
| S-29 (new) | The two maintain mirrors in `ST.SHAMAN.HUD_TEMPLATES` | a ruling on whether a template pick may **write** a mirror key on | an operator ruling: the templates' rule is "a pick writes the slot keys it lists" — so listing a mirror turns it on, which is a behaviour change beyond the widget+default scope the lane was given |
| The hunter's `practice_rotation` table shape (new) | the engine's rotation-table consumer | one shape: the hunter's table is a **per-family map** (`ST.HUNTER.PRACTICE_ROTATIONS[family]`), the sibling lanes' is a flat array filtered on `entry.family` | the shared-engine lane builds a consumer that accepts both, or every class moves to one shape |
| W-17 | The SoD stance-dance aura 426969 | a client source (0 hits in all four classic branches) | an in-client `UnitAura` probe on a SoD warrior in the stance-dance state |
| W-20 (build) | Devastate (TBC DW-arms rage > 60 filler) — **the id 25212 is the TBC Hamstring, not Devastate** | a TBC-arms branch, a 2H/DW read (Slam cast time > 0.5 s), and one guide slot (the TBC set is 7 of 8) | a TBC-arms APL fetch + the 2H read + a slot-budget ruling **+ the Devastate row's own id (currently unsourced — do not reuse 25212)** |
| DU-11 | The Rake DPE check | AP / DPE / proc inputs the class does not gather | a decision to gather them, or a documented cut |
| DU-12 | The clipRoar glyph extension | the Glyph-of-Shred / item-set inputs | a glyph-read decision (the sim's `MinRoarOffset` values are cited; the *read* is not) |
| DU-14 | Pooling as a cast-gate | the engine side (`pendingPool` → `floatingEnergy`) | an engine change + a class input |
| DU-15 | The trick windows | a rank table (or a client-resolved cost read) for Bite and Shred | a cost probe that resolves on the client |
| DU-18 / DU-21 | The Claw builder / position input | a facing source (no API answers facing) | documented cut, or a new client contract |
| DU-24 | The consumables / mana layer | a mana input + guide slots | a mana read decision (shared with P-22 and H-11) |
| DU-25 | bearweave / flowerweave / snekweave / powerbear | a bear timer / rage input | a documented scope cut (the current one) |
| R-12 | The Eureka-25 Tea line | the **name** is settled (1259812 = "Gnome Eureka", the Forever rogue APL's own variable) but the **client** source is still owed | a source, or the operator's in-client `GetSpellInfo` |
| R-16 | The Shiv EA-context check | the APL-literal EA-window design | a per-family minimum-EA window table + the Shiv-context rule |
| R-18 (rest) | The Vanish→Envenom sequence; Cut to the Chase | a slot/sequence state; an id for Cut to the Chase (the APLs carry none) | an APL fetch that names CtC, or a documented cut |
| R-19 (rest) | The CtC-anchored SnD refresh; Vanish→Overkill | the fight's remaining time in the guide inputs; a guide slot + prepull context | a fight clock in the guide inputs (the same gap as P-17) |
| R-20 | Tricks / Killing Sprie / **Venom** (1310703 — *not* "Riposte") | guide slots + APL-literal design (the rogue's 11 are frozen) | a slot-budget ruling |
| R-21 | The sweaty 0.5 s widening | in-client proof | an operator observation |
| R-22 | The retail sim verification | a retail sim repo in the brief set | a retail source, or a documented cut (the retail rows stay UNCONFIRMED) |
| P-05 | SoC scored 7 PPM, white hits only | a `twist.lua` change (the file is not the contract lane's) | the `twist.lua` edit + a `twist` suite pin |
| H-10 / H-16 / H-17 | The hunter's TBC Arcane, the trap tier, Readiness | guide slots (the hunter's set is full 6/6) + APL-literal rules | a slot-budget ruling for the hunter |
| H-19 | Sniper Training | a stationary/movement input | a movement read decision |
| H-23 | The Forever Multi conflict | an in-client answer on 1.60.x | the operator's session |
| H-24 | The Forever HHA sequence | the hawk count (H-22) + a sequence state | H-22 first |
| H-25 | The Forever Sniper range bypass | the Sniper-buff id (H-20) | H-20 first |
| U1 / U9 / U10 / U12 / U13 / U14 | The client-unconfirmed id sets | an in-client `GetSpellInfo` per id | the operator's session (the client FrameXML carries none of them — verified) |
| U3 | Victory Rush on Forever | moot for this release (operator SKIP) | a future VR lane |
| U15 | ISS mechanics | the numbers are SIM-side | the operator's session (the 12 s duration is page-confirmed) |
| S-26 | The twist rank (max vs downrank) | an operator ruling (§10) | the operator's ruling |
| DU-13 (assumption) | The Omen-ICD witness assumption | an in-client observation of the proc/lockout alignment | one operator observation |
| P-29 | Explicit 2pc-T10 DS set detection | a set id + an equipment probe | a documented nice-to-have (the readiness path already handles the behaviour) |

---

## 9. New findings from this sweep (defects in the filed corpus itself)

These are **not** in the original ledgers; they were found while re-examining them. They are
reported here rather than fixed, because this desk is read-only outside this one file.

**N1 — the rogue's TBC Sinister Strike / Hemorrhage ids are SWAPPED in the bench corpus.**
The corpus says "SS 26864 … Hemo 26862" (`bench/class_features_drills_2026-10-19.md:609`,
`bench/rogue_rotation_audit_2026-10-19.md:72`, and `bench/ids_research_2026-10-19.md` U10's
"26864/26863/34413/26862/…"). The client's own wowhead slugs say the opposite:
`https://www.wowhead.com/tbc/spell=26862` → **301** → `/sinister-strike` (title "Sinister
Strike") and `https://www.wowhead.com/tbc/spell=26864` → **301** → `/hemorrhage` (title
"Hemorrhage"). The other TBC rogue ids check out: 26863 Backstab, 26865 Eviscerate, 26867
Rupture, 34413 Mutilate, 26889 Vanish; 16511 Hemorrhage on both the /classic/ and /tbc/ slugs.
**Impact:** no shipped id is wrong today (the rogue resolves every spell **by name**), so this
is a documentation defect — but the *sim-side* id would be wrong if a lane ever wires an id
table. The fix is BS-6 (name-based) plus a bench correction.

**CLOSED as a corpus defect 2026-10-20** (desk `corpus-corrections`): the three corpus
places this section named now carry the **corrected** pairing, each with a dated note:
`bench/class_features_drills_2026-10-19.md` (R-03), `bench/rogue_rotation_audit_2026-10-19.md`
(§1's TBC builder branch) and `bench/ids_research_2026-10-19.md` (U10). The rogue APL build
lane's sim-sourced TBC table independently agrees — `hemorrhage` **26864** / `backstab`
**26863** / `mutilate` **34413** (`bench/rogue_apl_utility_build_2026-10-20.md` §1.1 rows
34-36). **26862 = Sinister Strike, 26864 = Hemorrhage.**

**N2 — the druid's "no honest probe" comment is factually wrong.**
`classes/druid.lua:1875-1876` says "no Wolfshead Helm item id is verified in this codebase (so a
GetInventoryItemID read would be a guess)". Both halves are false today: the id 8345 is
web-confirmed (`bench/ids_research_2026-10-19.md` §2) and the read exists
(`compat.lua:986` `api.GetInventoryItemID`). The *client* read is also client-sourced, with the
slot number in the client's own `Constants.lua`. BS-2 fixes the code and the comment.

**N3 — the shaman's CoE "UNCONFIRMED against the client's FrameXML" is stale.**
`classes/shaman.lua:4012` (and `bench/shaman_slots_2026-10-19.md` §2, and
`bench/shaman_drills_2026-10-19.md` §2 S-20) call the water slot "UNCONFIRMED against the
client's own FrameXML". It is confirmed: `classic_titan:Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:288`
→ `WATER_TOTEM_SLOT = 3;` — and the addon's own `compat.lua:1064` already documents the map
("Slots are 1=Fire, 2=Earth, 3=Water, 4=Air"). The `66842` id is likewise client-sourced
(`:300-304`).

**N4 — the hud-guide "no target-aura scan exists" framing is wrong.**
`bench/hunter_rotation_drills_2026-10-19.md` §4 H-04 says "the **target-debuff read** does not
exist (compat.lua exposes no target-aura scan)". `compat.lua`'s `api.UnitAura(unit, index, filter)`
(`:456-488`) is already unit-generic — what is missing is only a scan helper. BS-3.

**N5 — the guide's own "guide contract is frozen" claim is a per-file pin, not a policy.**
The frozen counts are the pins at `tests/guide_contract.lua:689` (paladin 10), `:1353` (rogue 11),
`:1514-1515` (shaman 17) and `:1550` (shaman HUD 10). A slot addition is therefore a **pin
update plus an append-only section edit**, not a contract renegotiation — which is why BS-4a
(18th shaman slot) and BS-9 (warrior HUD mirrors) are buildable while the "frozen" rows
(H-10, H-16, H-17, R-20, §5.1) stay filed: those need a *ruling* because the *engine* would need
a new rule, not because a pin exists.

**N6 — the tbc-new sim's class directory layout is `ui/specs/<class>/<spec>/apls/`, and the
sod sim's is `ui/<class>_<spec>/apls/`.** Two of the corpus's URL guesses 404 for this reason
(`ui/paladin/apls`, `ui/shaman/apls`). The confirmed paths are
`wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json` and
`wowsims/sod ui/retribution_paladin/apls/p8-*.apl.json`. Worth carrying into the next research
lane so nobody re-404s them.

**N7 — the wowsims `master` energy model has drifted.** `wowsims/classic sim/core/energy.go`
now declares `EnergyTickDuration = time.Millisecond * 2020` and `EnergyPerTick = 20.2` (the
durable rate is still exactly 10.0/s, but the cycle is 2020 ms, not 2000 ms). The addon's
`druid_energy.lua` freezes 2.0 s / 20. Not a defect, but any new citation must carry **both**
numbers or it will look like a contradiction. (Flagged, not changed — the druid lane owns it.)

---

## 10. Operator decisions owed (a research sweep cannot close these)

| # | Decision | Why it is an operator call | Current standing |
|---|---|---|---|
| O-1 | **S-26 twist rank** — max-rank 25587 (what the sim twists) vs the module's downrank note | two shipped behaviours are both defensible; the sim is not the client | filed, unchanged (`bench/shaman_drills_2026-10-19.md` §2 S-26) |
| O-2 | **Hunter slot budget** — H-10 (TBC Arcane), H-16 (traps), H-17 (Readiness) all want a 7th/8th slot | the guide's 6-slot set is full; raising it is a product decision | filed; the pin is at `tests/guide_contract.lua` |
| O-3 | **Rogue slot budget** — R-20 (Tricks / Killing Spree / Riposte) and §5.1 (a 12th slot for Hunger for Blood) | same, at 11 slots | filed |
| O-4 | **S-11 Chain Lightning enemy count** — accept a non-client count source, or cut the rule | no client API exists; this is a fidelity-vs-honesty call | filed |
| O-5 | **W-20 Devastate** — accept a TBC-arms branch that prompts below HS, or cut | the sim ranks it below HS, which the engine's first-match-wins shape cannot express | filed |
| O-6 | **F13** — measure the trim cost, or convert the combat-path sites | bounded today, but "bounded" was never measured | filed |
| O-7 | **Victory Rush** — the operator already ruled SKIP; this row records that the Forever id question is deferred, not closed | — | closed for this release |

---

## 11. Validation and honest limits

**What this desk did:** read the whole filed corpus; re-read the shipped tree at the cited
lines; read the client source of five client branches read-only; fetched a bounded set of public
sim/web sources. One new bench file written. No addon file, no test file, no other bench file,
no TOC, no version, no `Libs/` change. No git write of any kind on the addon repo.

**What this desk did NOT do (and did not claim):**

1. **No in-client verification.** Every "CLIENT-UNCONFIRMED" label in the corpus stands. This
   sweep closes *evidence* gaps, never *behaviour* gaps. The standing caveat (U-14) is unchanged
   and is the biggest remaining risk in the release.
2. **No harness run, no luacheck run.** This desk changed no code, so a run would prove nothing
   about it; the orchestrator owns the in-tree validation of every build spec in §7.
3. **No new ids were invented.** Every id in this file is attached to a URL or a
   `branch:file:line` that was actually read this session, or is explicitly marked
   SIM-CONFIRMED-only / still-unconfirmed.
4. **The sims move.** Several citations are to `master` as fetched today; the wowsims master
   branch drifts (see N7). A build lane that re-verifies a number should re-fetch the file, not
   trust this document's line numbers.
5. **`wowhead` `/forever/` pages are bot-walled to this session's scraper** (HTTP 403 on a
   re-fetch of `spell=10333`); the ids_research snippets stand as the source for the Forever
   ids. The `/tbc/`, `/classic/` and `/wotlk/` slugs were read live and are quoted by redirect
   target + page title.
6. **The build specs are specs.** §7 says what to change, in which file, with which pin, and
   under which lane — but the orchestrator still validates each one in-tree before the next
   phase starts, per the plan's standing rules.

**Suggested order for the next wave** (all disjoint; BS-1 first because BS-2 and BS-3 depend on
it): BS-1 → (BS-2, BS-3, BS-6 in parallel) → BS-4 → BS-5 → BS-7 → BS-9 → BS-8.

**Validation owner: orchestrator.**
