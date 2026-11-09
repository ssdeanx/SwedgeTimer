# Deep feature / reliability / enhancement audit — 2026-10-25

Desk: `audit-features` (shell-capable, read-only by scope). **No product code was edited.**
Scope: `classes/*.lua`, `practice*.lua`, the guide engines/UI, `twist.lua`, `weave*.lua`,
`druid_energy.lua`, `rotationtext.lua`, `design*.lua`, `widgets.lua`, `option_tables.lua`,
`config_presets.lua` (plus `hud.lua`/`main.lua`/`bars.lua` where they route class features).

## 0. Snapshot, method, and a moving tree

**The tree was being edited while this audit ran.** `practice_ui.lua`, `practice.lua`,
`main.lua`, `config.lua`, `option_tables.lua`, `config_presets.lua` and `classes/hunter.lua`
all changed between 12:38 and 12:57 on 2026-10-25 (the in-flight "moving cue strip" /
hunter bar work). Findings below were re-verified against the **12:57–12:59 snapshot**;
line numbers are that snapshot, snippets are the stable key. Fingerprints at snapshot:

| file | md5 | file | md5 |
|---|---|---|---|
| classes/druid.lua | 482dd172… | practice.lua | dc246401… |
| classes/hunter.lua | 4d95ae23… | practice_ui.lua | f43db22b… |
| classes/paladin.lua | 2a5422cd… | practice_progress.lua | b7e9f8df… |
| classes/rogue.lua | a9c5da9d… | practice_progress_ui.lua | eb9a6895… |
| classes/shaman.lua | 421db56a… | practice_stats.lua | de1996a3… |
| classes/warrior.lua | d67f2966… | hud.lua | 33b49cf4… |
| main.lua | 7b3a617b… | nextaction_ui.lua | e13df822… |
| bars.lua | 76455dfb… | hunter_guide.lua | 6f5ac8bf… |
| option_tables.lua | a21d1c7b… | hunter_ui.lua | 4f40530c… |

**Transient red, now green (watch item, not a release blocker).** While the playhead wave
was landing, `practice_ui_state.lua` was red from ~12:44 to ~12:52 (10 failures in the
timeline area — frame count 83 vs 70, "History" button label, pooled icon/divider/ruler
counts, auto-scroll). At the final 12:59 snapshot it **passes 2608/0**, and `smoke.lua`
(232/0) and `wiring_check.lua` (873 checks / 0 failures / 3 accepted) are green. The lesson
is the process one: the tree was committable-looking while a suite was red — always re-run
the suite after a wave lands and before a commit.

## 1. Behaviour correctness vs documented intent

### 1.1 What each class actually reaches

All six modules publish the full provider set (`guide`, `HUD_SLOTS`, `practice_panel`,
`practice_scenario_step`, `practice_drills`, `practice_neutral_actions`), verified by
`grep` + the green class suites. The dispatch graph is complete for the **playing** class
(`wiring_check` §1/§2/§6 green).

| class | guide | HUD | practice | other promised systems |
|---|---|---|---|---|
| Warrior | `ST.WARRIOR.guide` (classes/warrior.lua:4147), engine `warrior_guide.lua` | `HUD_SLOTS` built per family/spec (classes/warrior.lua:4337-4391) | 6 drills (classes/warrior.lua:5921); class mode routes to the drill list (§1.3) | HS/Cleave queue (`get_bank_state` :1916, `gate_composite_action` :1962 → guide :4168); Execute report (`track_execute_phase` :2081 → practice_ui.lua:7282) |
| Paladin | `ST.PALADIN.guide` (classes/paladin.lua:3649) + `nextaction.lua`; twist band | `HUD_SLOTS` (classes/paladin.lua:3833), JotC bar `setup_jotc_bar` :2802 | twist sim (`practice.lua` `ABILITIES` :86 + paladin `practice_sync`), 3 drills (:6366) + twist drill | seal icons, twist glow, twist text, AOW pulse (`process_aow` :817) — wired from `on_aura_change`/CLEU |
| Hunter | `hunter_guide.lua` (family matrices) | `HUD_SLOTS` family rows; cast bar / range helper / RF bar / aspect / trap badge (`hunter_ui.lua`) | forced-move session (`PRACTICE_SHOTS` classes/hunter.lua:1957) + 4 drills (:4982+), shot report (practice_ui.lua:7160) | trap tracker (`note_trap_cast` :1826, `get_trap_remaining` :1866 → badge hunter_ui.lua:1360); **weave-progress integrator exists but is write-only** (§1.4) |
| Rogue | `rogue_guide.lua` (pool/spend, Rip-vs-Evis, Envenom, Shiv/Tea) | 13 slots incl. SnD/Rupture/EA/AR/BF/ColdBlood | energy-pool session + 4 drills; Era SS-after-swing session | energy tick sampler (`update_energy_tick` :658), visuals (`update_rogue_visuals` :1751) |
| Druid | `druid_guide.lua` (Bite/Rip, FF fishing, `rip_min_cp` override) | 11 slots incl. TF/Berserk (`HUD_SLOTS` :2580, Mangle Era-rune hide :2814) | powershift session + 4 drills (:3902) | energy trackers + Omen/TF procs (`druid_energy.lua`, `update_druid_player_buffs` :1095) |
| Shaman | `shaman_guide.lua` (weave fits, sub-5 LB/LvB, totems) | family slot sets (`family_guide_slots` :4994, `apply_family_slots` :5033) | weave session + 4 drills (:5218) | weave marker/cast spark (`setup_weave_visuals` :1492), totem clocks (:1039-1219) |

Gate checks that are frequently over-claimed, and their evidence:

- **README :50 "All six classes ship a rotation scenario"** — true: every module defines
  `practice_scenario_step` (six `grep` hits) and `H.practice_scenario_available`
  (practice.lua:3701+ contract) only needs that member.
- **README :90 "three curated templates for each of the six classes (18 in all)"** — true:
  `config_presets.lua` has exactly 3 keys per `ST.<CLASS>.HUD_TEMPLATES` (verified by parse:
  druid 3, hunter 3, paladin 3, rogue 3, shaman 3, warrior 3).
- **README :51-56 "three to six focused drills each"** — true: paladin 3 + twist, druid 4,
  hunter 4, rogue 4, shaman 4, warrior 6 (`practice_drills` tables).
- **README :75 "The scenario is timed off the swing"** — **FALSE as written.** The shared
  rotation scenario opens a step and closes it on a fixed 3.0 s deadline
  (`practice_ui.lua:172 SCENARIO_STEP_SECONDS = 3.0`; `scenario_open_step` sets
  `deadline = now + SCENARIO_STEP_SECONDS` at :4867). The swing engine is used only as a
  *gate* (`practice_swing_engine_dead`, :580-586). See §1.3.

### 1.2 HIGH — the `class_activation` option is half-wired (silent no-op)

The option promises: *"picking a class activates that class's module instead. Only the
selected class is loaded"* (`option_tables.lua:233` help text, quoted in
`bench/class_activation_2026-10-21.md`). The loader does populate that module
(`main.lua:747-792`, `active_class` at :791), but **every live class route still keys on
`player_class`**:

- `ST:post_init` runs `self[self.player_class].post_init` — `main.lua:970`.
- Event/class dispatch: `main.lua:1098, 1757, 1863, 1999, 2013, 2236, 2245, 2253, 2303`.
- Bar class hooks: `bars.lua:905` and `bars.lua:1347` (`local class = self[self.player_class]`).
- Guide provider: `nextaction_ui.lua:135` (`self[self.player_class or ""]`).
- HUD provider: `hud.lua:524` (`ST[self.player_class or ""]`), which then returns the
  "silent no-op" at `hud.lua:537-540` when the slots table is nil.
- Progress page scope: `practice_progress_ui.lua:202-228`
  (`wanted = ST.player_class`).

Consequence, provable from code: with `class_activation = "PALADIN"` while playing a
warrior, `ST.PALADIN` is loaded but **its `post_init` never runs**, so `hud.init`,
`nextaction_ui.init` and `practice_ui.init` are never called for it; the HUD/guide/visuals
stay inert. Practice is the exception — `practice_ui.practice_class_module` correctly uses
`ST.active_class` (`practice_ui.lua:373-386`), so a session can be started by
`ui.start`'s `pcall(ui.init)` path (`practice_ui.lua:5441-5448`), but its XP is written to
the PALADIN scope while the **Progress page reads the warrior scope**
(`practice_progress_ui.lua:202-228`) — the player earns XP they cannot see.

The activation suite only asserts the selected table is populated
(`tests/class_activation_state.lua:261-281`), never that its `post_init`/hooks ran. This is
why the suite is green while the option is broken.

**Fix options (operator ruling needed):** (a) narrow the option to "practice/preview class"
and label it so, keeping live HUD/guide on the played class, plus make the Progress page
read `active_class`; or (b) introduce one `ST:class_route()` =
`self.active_class or self.player_class` and use it in `post_init`, the event hooks, bars'
class hooks, `hud.create`, `nextaction_ui.get_provider` and the progress page. (b) makes the
selected class's spell ids drive live bars on a character of another class — likely
incoherent; (a) is the safer correction. **UNVERIFIED in-client** either way.

### 1.3 MEDIUM — the rotation "scenario" is a 3-second quiz, not a swing-timed run

`scenario_open_step` shows the wanted action and its reason in the panel
(`practice_ui.lua:5047-5084`, `practice_row_prompt("next: " .. expected .. " - " .. reason)`),
and the player presses a button; `scenario_cast` grades only via those buttons (:4980).
Steps close on a fixed 3 s deadline (`:4867`) regardless of the class's swing/GCD. So:

- it cannot train swing-timed execution (the addon's whole subject), despite README :75;
- the answer is printed in the prompt, so a run is completable by clicking the named
  button — 10 correct clicks = an S run (see §3.2);
- a class's own clip/weave logic is asked about at 3 s cadence, not at the decision moment.

This is a design gap, not a crash. **Where:** practice_ui.lua:4867 + scenario_open_step;
practice.lua's `rotation_run_decide` (3960) is sound as a decision engine.

### 1.4 MEDIUM — hunter "Melee-weave progress tracking" is a write-only state

`st.hunter_weave_prog` / `_dir` / `_prev_melee` / `_last_t` are written by
`ST.HUNTER.update_weave_prog` (`classes/hunter.lua:2264-2297`) when the opt-in
`hunter_weave_prog_enabled` is exactly true (`:2269`), and **nothing ever reads them**
(`grep` across the tree: only the option key and the two live writes). The option's own
description is honest — *"No visible change on its own: a future display reads this state"*
(`option_tables.lua:4634-4641`) — but the feature is dead weight today. Given the
operator's melee-weave focus this is the natural hook for enhancement E1/E2 (§8).

### 1.5 MEDIUM — the Sniper range bypass is unreachable

`inputs.sniper_range_buff_active = nil` is hardcoded (`classes/hunter.lua:3326`), while the
guide's out-of-range hold is `target_in_range == 0 and inputs.sniper_range_buff_active ~= true`
(`hunter_guide.lua:931`). The bypass branch can therefore never fire on the Forever MM
client it was written for. The comment (:3318-3320) says "no source yet (filed), so it stays
unknown", so this is a known gap — but the code reads as a shipped rule. Either implement
the buff read or drop the field/branch and say so in the header.

### 1.6 LOW/MEDIUM — hunter practice sim cast times are family-blind

`PRACTICE_SHOTS` (`classes/hunter.lua:1957-1961`) hardcodes Steady 1.5 s, Multi 0.5 s,
Aimed 3.0 s and the panel order `{steady, multi, aimed}` (:1962, wired at :5783). The
comment says this is deliberate ("the drill is a sim, so the family never gates the shot
list"). It still teaches a 3.0 s Aimed on Wrath (instant 49050) and offers Steady on Era
where the spell does not exist (the module's own comment at :5286-5290 says so). A
family-aware cast table is cheap; see F9.

### 1.7 LOW — dead code / debug surface (pre-existing)

- `ST:configure_gcd_underlay` (`bars.lua:528`) has **no caller**; the live path paints the
  GCD texture at `bars.lua:359-361`, so this is a duplicate owner. Remove it.
- `ST:is_value_in_array` (`main.lua:163`) has no caller.
- `ST:test1` + `RegisterChatCommand("test1", "test1")` (`main.lua:2794-2797`) register a
  permanent global slash command that does nothing. Remove (namespace pollution; possible
  collision with another addon).
- `widgets.lua:77-91` (`recover_class_sound_map` via `debug.getupvalue`) is unreachable in
  every working case: the paladin publishes `ST.PALADIN.twist_sounds`
  (`classes/paladin.lua:1140`) and `sound_map()` checks that before the upvalue probe
  (`widgets.lua:105-113`). Delete the bridge.

### 1.8 LOW — shared file still hosts class-specific report builders

`ui.build_hunter_report` (`practice_ui.lua:7160`) and
`ui.build_warrior_execute_report` (`practice_ui.lua:7282`) are class-specific features in
the shared UI (already filed in `bench/class_isolation_2026-10-21.md` §8). They reference no
class table, so §10 passes, but the natural home is the class providers.

## 2. Class isolation

### 2.1 What the §10 guard covers, and what it misses

`tests/wiring_check.lua:1888-1948` scans ten shared files for **`ST.<CLASS>` / `st.<CLASS>`
in executable code**, and pins `active_class` in exactly two route owners
(`practice_ui.lua`, `rotationtext.lua`). It reports 13 `ST.<CLASS> = {}` namespace
definitions in `main.lua` (floor 6) and passes.

Literal `ST.<CLASS>` sites in shared files at snapshot (all in data/config, none in a route):

- `main.lua:66,68,71,73,74,76` — `ST.DRUID/HUNTER/PALADIN/ROGUE/SHAMAN/WARRIOR = {}`
  (the activation mechanism's own tables; the sanctioned exemption).
- `config_presets.lua:313,449,485,619,678,867,932,1091,1127,1243,1309,1474` —
  per-class `defaults` / `HUD_TEMPLATES` data tables (loaded for all six, independent of
  activation; correct).

**Blind spots the guard does not see:**

| coupling | where | why it matters |
|---|---|---|
| `self[self.player_class]` class dispatch | main.lua:970, 1098, 1757, 1863, 1999, 2013, 2236, 2245, 2253, 2303; bars.lua:905, 1347 | bypasses `active_class`; the activation option's core defect (§1.2) |
| `ST[self.player_class]` provider lookup | hud.lua:524; nextaction_ui.lua:135 | HUD/guide dead under an explicit non-playing pick |
| `ST.player_class` scope selection | practice_progress_ui.lua:202-228 | Progress page shows the played class while XP is written to the active class |
| literal `self.HUNTER` / `player_class == "HUNTER"` | main.lua:1788, 2444 | class-specific logic in shared code, invisible to §10 (it only matches `ST.HUNTER`) |
| `ST.player_class` display/default lookups | designmode.lua:131,146; option_tables.lua:219,476-498; widgets.lua:44,78,106 | benign for Auto, inconsistent under an explicit pick |

**No class module reads another class module** (swept all six for `ST.<other>` — zero hits),
and no product file indexes `ST[ST.active_class]` unguarded. The class modules themselves
are cleanly isolated.

### 2.2 Verdict

The **practice/rotation-text half** of the 2026-10-21 isolation contract is implemented and
machine-enforced. The **live-feature half** (post_init, event hooks, bars, HUD, guide,
progress page) still keys on `player_class`; the option that made this visible
(`class_activation`) is consequently half-broken. The guard should grow a
`self.<CLASS>`/`self.player_class == "<CLASS>"` leg so this class of coupling cannot hide
behind the `ST.` pattern (F10).

## 3. Practice integrity

### 3.1 What holds (verified)

- **Idling cannot farm.** A non-hold step with no cast is a `miss` → F (zero points); a
  stated hold with no cast is `hold_ok` and the grade map deliberately has **no entry** for
  it or for `neutral` (`practice.lua:3922-3946`, `H.ROTATION_OUTCOME_GRADES`, practice.lua:3922). A class's
  `nil` answer is `unknown` and records nothing (`:3960-4000`). This is the HU-8 rule and it
  is correctly implemented.
- **Holds vs unknown are distinguishable** end-to-end: `H.practice_scenario_step`
  (:3701-3724) only promotes `{action=nil, hold=true}` to a hold; anything else nil is
  unknown.
- **Sessions are class-scoped** (`practice_ui.lua:1071-1077`, `progress_class_key` =
  `ST.active_class`) and the class's own drills/scenario own the drill key
  (`:1091-1113`). There is **no family dimension** in progress (`practice_progress.lua`
  scopes by `class_key` only); that is acceptable because SavedVariables are per client
  install, but it means a TBC-specific drill (e.g. `hunter_kill_command`, which returns nil
  outside TBC — classes/hunter.lua:5050-5060 region) shares a mastery row with the same
  key used nowhere else. Note it, do not "fix" it.
- **A wrong class cannot farm another class's progress**: only the active class's module is
  consulted, and a missing module refuses loudly (`practice_ui.lua:5513-5515`).

### 3.2 HIGH — grading is answer-revealed and re-clickable

Two independent holes multiply:

1. **Answer revealed.** The scenario prompt prints the exact wanted key
   (`practice_ui.lua:5075-5084`), and the action row contains that key. Clicking the named
   button always produces `correct` → S (`practice.lua:3994-3998`, map at :3922-3926).
   Ten clicks = an S run; no rotation knowledge is required.
2. **Drill buttons grade the same moment repeatedly.** `drill_list_press`
   (`practice_ui.lua:5329`) and `drill_list_pick_press` (:5304) call `drill_list_grade`
   (:5248) on every click with no time/event gate; `H.practice_drill_grade`
   (`practice.lua:3775-3788`) is a pure call into the class grader. A moment-grader such as
   `hunter_kill_command` (classes/hunter.lua:5050-5080: "Kill Command is up → S") answers S on
   every click while that state holds. Even the priority drills can be re-graded by
   re-clicking the pick (`drill_list_pick_press` → `drill_list_grade` immediately).
3. **The XP cap does not cap the other ledgers.** XP is capped at
   3× the drill's median hit (`practice_progress.lua:450-457`, applied :694-706), but
   `practice_ui.record_graded_attempt` feeds the **stats** ledger unconditionally
   (`practice_ui.lua:1438-1454`), and `practice_stats.record_attempt` increments
   `attempts/hits/points/s_run/best_s_streak` (`practice_stats.lua:275-302`). Achievements
   read those: `perfect_ten` = `best_s_streak >= 10` (`practice_progress.lua:1070-1076`).
   Ten S clicks unlock it without a single in-game action; accuracy/mastery inflate too.

**Fix:** (a) debounce a drill grade on a real advance (one attempt per swing/GCD/per
distinct moment — e.g. latch the last graded moment key + timestamp in the drill session);
(b) make `drill_list_pick_press` only set the pick, never grade; (c) add a "test mode" that
hides the prompt (`next:` becomes `?`) so graded runs are meaningful, gated by an option
(nil = off).

### 3.3 MEDIUM — the pick channel double-fires as a grade

Pressing an action button in the drill list both selects the pick *and* grades the currently
selected drill with it (`drill_list_pick_press`, practice_ui.lua:5304-5325 →
`drill_list_grade(self, drill_key, action_key)`). A player exploring the buttons records
attempts (possibly F, breaking the session streak) on a drill they did not intend to run.
Separate "pick" from "grade".

### 3.4 MEDIUM — timelines: paladin-only log, synthetic generic strip

The post-fight timeline/bands are the paladin sim's (`practice.lua` bands/timeline lanes
:133-150, `ui.build_timeline` practice_ui.lua:3365) and are not driven by the class drills.
The new moving strip (current-wave, `ui.build_timeline`/`playhead_*`, practice_ui.lua:3585+)
is generic, but with **no class publishing `panel.upcoming`** it always falls back to
`st.practice.timeline_cadence` (`practice_ui.lua:3861`; practice.lua:608) — a synthetic
GCD-cadence preview anchored to the fight start, not real cooldowns/swing. The title says
"Rotation cadence (preview)" (:3864), which is honest, but it is not the "next action in X
seconds" a player will read it as. See E11.

## 4. Per-client feature drift

### 4.1 HIGH — the Era/SoD ranged-range probe points at a spell the client does not have

`steady_id_by_family.ERA = 56641` (`classes/hunter.lua:179-180`), and the guide's range
probe is `spell_token(steady_current_id or guide_slot_steady.spell_id)` → `IsSpellInRange`
(`classes/hunter.lua:3331-3338`). Evidence from the operator's own 1.15.9 client data:

- `/home/sam/wow.export/Spell.csv` has **35,313 rows and no `56641;` row**; `2973` (a real
  vanilla spell) is present, so the export is not truncated.
- The only "Steady Shot" text in that data is the **SoD rune 409957** ("Gain the Steady
  Shot ability"), not an ability id the ladder knows.

So on Era and SoD the range token does not describe the running client's ranged spell;
`inputs.target_in_range` cannot return "in range", and the guide's out-of-range HOLD
(`hunter_guide.lua:931`) can never fire there. (Whether the client returns nil or 0 for the
unknown id is **UNVERIFIED offline**; either way the probe is wrong.) **Fix:** probe the
family's actual ranged spell — Auto Shot (75) on Era/SoD (it exists in the 1.15.9 data), the
resolved Steady rank on TBC/Wrath.

### 4.2 Verified TBC name discipline

All six classes gate the state APIs by family (Era ids, TBC names): druid 10 TBC gates,
hunter 4, paladin 5, rogue 3, shaman 11, warrior 5; the representative resolvers are
`hunter_ui.resolve_spell` (hunter_ui.lua:180-190), `spell_token` (classes/hunter.lua:25-33),
rogue `resolve_named_spell` (classes/rogue.lua:200-245), paladin/warrior/druid equivalents.
No raw-id `api.GetSpellCooldown/IsSpellInRange/IsSpellKnown` call exists outside the id
tables (swept all six: only comment citations match).

### 4.3 Other family-specific gaps

- **Sniper range buff** hardcoded nil — §1.5 (Forever MM).
- **Hunter practice sim** family-blind cast times — §1.6 (Wrath Aimed, Era Steady).
- **`hunter_weave_prog`** is family-neutral but unused — §1.4.
- **FOREVER/CATA/MISTS** cells are deliberately empty in the hunter slot maps where the
  client has no spell (e.g. raptor Mists) and the HUD dead-slot filter drops them — verified
  in the tables at `classes/hunter.lua:211-300`.
- **Cata/Mists** are unsupported clients (README :15-17); their inert stand-in path is
  consistent with the docs.

Anything beyond the above (per-class spell-id correctness on TBC/Wrath/Forever, aura id
legs, totem ids) is **UNVERIFIED offline**; only the operator's in-client log can close it.

## 5. Performance (only what the code proves)

1. **MEDIUM — hunter guide gather does 3-6 full aura walks per 50 ms tick.**
   `nextaction_ui.lua:113 UPDATE_INTERVAL = 0.05` calls `provider.gather` every compute
   tick. The hunter gather loops every applicable utility spec and calls
   `utility_buff_active` / `utility_debuff_active` per row (`classes/hunter.lua:3238-3260`),
   each a fresh closure + a full `api.scan_unit_aura` walk (cap 40 rows,
   `compat.lua:593`, `:650+`), plus `read_serpent_active` (classes/hunter.lua:2832-2855)
   which walks the target again. On TBC that is `aspect_viper` + `aspect_hawk` (player) +
   `serpent` (target) = 3 walks/tick ≈ up to 120 `UnitAura` calls per 50 ms; Forever adds
   `hunters_mark`. Compare the druid, which does **one** shared player scan per tick
   (`classes/druid.lua:1095-1113`). **Fix:** one player snapshot + one target snapshot per
   gather, matched against all specs; keep the reused tables. Removes the per-row closures
   as well.
2. **LOW — `practice_ui.update_info` allocates a format string every 50 ms** but latches
   before `SetText` (`practice_ui.lua` `if text ~= ui.last_info_text`), so no frame churn.
   Fine.
3. **LOW — `nextaction_ui`/`hud` are rate-limited and pooled** (icons reused; one
   `OnUpdate` each; `SetCooldown` set-once pattern). No per-frame frame creation found.
4. **LOW — hunter `update_trap` runs for every hand** (`classes/hunter.lua:1150-1152`
   calls it before the hand gate), but it is a nil check + one clock compare when no trap is
   live. Acceptable.
5. **Current-wave — the moving strip's `OnUpdate`** does arithmetic + `SetPoint` on a
   pooled icon set (`practice_ui.lua:3832+`); the schedule rebuild is throttled
   (`PLAYHEAD_SCHEDULE_INTERVAL`). No allocation found in the draw path; keep it that way.
6. **Not proven / not flagged:** no per-frame `GetSpellInfo` in any guide (rank resolvers
   are cached and throttled); no HUD slot rebuild on tick (layout only).

## 6. Reliability

1. **MEDIUM — `pcall` hides a permanently broken class step/grader.**
   `H.practice_scenario_step` calls the class step under `pcall` and turns *any* throw into
   `nil` = UNKNOWN (`practice.lua:3701-3710`); `H.practice_drill_grade` does the same for a
   grader (`:3775-3788`). A class step that throws forever yields a run of ten UNKNOWN
   steps and the UI says "run unknown" — no error line, no guard counter, `/st diag` stays
   clean. The practice UI's own compute path *does* use `st.guard` (`practice_ui.lua:5887-5896`), so this path is the odd one out. **Fix:** route these pcalls through
   `st.guard.run(self, "practice:class-step", …)` (first throw printed once, counted,
   quarantined) and keep the nil-to-UNKNOWN mapping.
2. **MEDIUM — file-scope clobber of `ST.player_class` in the options file.**
   `option_tables.lua:79-81` does `local _, english_class = UnitClass("player")` and
   `ST.player_class = string.lower(ST.player_class_pretty)` at load. `main.lua:392` later
   sets the real uppercase token, so today it is repaired before use — but any error between
   the two leaves `player_class` lowercase, and every `profile[player_class]` /
   `ST[player_class]` lookup then misses silently (class table nil → features inert).
   Nothing needs the file-scope write. **Fix:** delete line 81 (main owns the field), or make
   it `ST.player_class = ST.player_class or string.lower(...)`.
3. **HIGH — the activation/post-init split** (§1.2) is also a reliability defect: a
   supported option produces a session with a loaded module and no initialised features, and
   nothing logs it.
4. **LOW — guard quarantine is session-long.** After 25 throws a site stops being called and
   the player gets a one-time notice (`guard.lua` contract, used by nextaction/practice).
   That is a deliberate downgrade, but for `nextaction:gather` it means the guide is
   permanently blank for the session with no recurring signal; `/st diag` should be checked
   in that state (it is counted). No change requested.
5. **LOW — latches:** `hunter_weave_prog`/`_dir` reset on combat exit
   (`classes/hunter.lua:1249-1265` region) and on the opt-in gate; `hud_tf_live`/
   `hud_berserk_live` latch positive answers forever (correct — spell knowledge does not
   change mid-session except rune swaps; a rune swap is not observed, UNVERIFIED).

## 7. Top 12 concrete fixes (ranked)

| # | sev | fix | file:line | one-line change |
|---|---|---|---|---|
| F1 | **HIGH** | Make `class_activation` coherent (or narrow it to practice/preview) and fix the progress-page scope | main.lua:970, 1098-2303; bars.lua:905,1347; hud.lua:524; nextaction_ui.lua:135; practice_progress_ui.lua:202-228 | one `ST:class_route()` = `active_class or player_class` for post_init/hooks/providers; progress page reads `active_class` |
| F2 | **HIGH** | Era/SoD range probe uses a spell absent from the 1.15.9 client | classes/hunter.lua:179-180, 3331-3338 | probe Auto Shot (75) on ERA/SOD, resolved Steady on TBC/WRATH |
| F3 | **HIGH** | Stop answer-revealed/re-clickable grading from inflating ledgers | practice_ui.lua:5047-5084, 5248-5335; practice_stats.lua:275-302 | debounce per drill moment; pick press must not grade; optional hidden-answer mode |
| F4 | MED | Scenario timing: time steps off the swing or correct README:75 | practice_ui.lua:172, 4867 | open the next step on the swing/GCD boundary (or delete the "timed off the swing" claim) |
| F5 | MED | One aura snapshot per hunter gather | classes/hunter.lua:2832-2855, 3238-3260 | pass a per-tick player/target snapshot into all specs |
| F6 | MED | Report a permanently broken class step/grader | practice.lua:3701-3710, 3775-3788 | wrap the pcalls in `st.guard.run` |
| F7 | MED | Remove the file-scope `player_class` clobber | option_tables.lua:81 | delete (main.lua:392 owns it) or `or`-fallback |
| F8 | MED | Implement or remove the Sniper range bypass | classes/hunter.lua:3326; hunter_guide.lua:931 | read the buff aura (Forever MM) or delete the dead branch |
| F9 | MED | Family-aware hunter practice cast times | classes/hunter.lua:1957-1962 | per-family Steady/Multi/Aimed seconds + order |
| F10 | LOW | Close the §10 blind spot for `self.<CLASS>` / `player_class ==` coupling | tests/wiring_check.lua:1900-1928; main.lua:1788,2444 | scan `self%.<CLASS>` + `player_class%s*==%s*"<CLASS>"`; move the hunter branches behind a provider |
| F11 | LOW | Delete dead code/debug surface | bars.lua:528; main.lua:163,2794-2797; widgets.lua:77-91 | remove the four dead items |
| F12 | LOW | Move class-specific report builders out of shared UI | practice_ui.lua:7160, 7282 | register them through the class `practice_panel` |

## 8. Top 12 enhancements (value / effort)

| # | value/effort | what it adds | why the operator cares | where |
|---|---|---|---|---|
| E1 | **high / low** | Feed `hunter_weave_prog` + distance into the existing `weave_range` bar: draw the melee band and a "weave safe window" marker from the Auto Shot cycle and travel time | The bar is already ON for hunters (`config_presets.lua:536`) and the integrator already runs; this turns a dead toggle into the melee-weave coach the operator is asking for | `weave_range.lua` draw + `classes/hunter.lua:2264` |
| E2 | **high / medium** | Add a "weave now / stay" decision to the hunter guide: when melee abilities are ready and the next Auto Shot leaves a gap, prompt `weave: Raptor` (with travel time), else a `HOLD` for shots; use the TBC APL's wait-at-melee 400 ms | Melee weaving is the operator's current focus; the guide currently only acts *after* you are already in melee (`weave_band == "melee"`), never tells you to go | `hunter_guide.lua` (new rule above the clip arms) + `classes/hunter.lua` gather |
| E3 | **high / medium** | One-bar overview: a compact "next 3 actions" strip driven by real cooldowns/swing (generalise the new playhead beyond practice, or add `panel.upcoming`) | Fewer windows/clicks; one glance answers "what now" across all six classes | `nextaction_ui.lua` + class providers (`panel.upcoming`) |
| E4 | **high / medium** | Grade **real** casts in the scenario: listen to `UNIT_SPELLCAST_SUCCEEDED` (and the class's own `on_spellcast_event`) instead of only panel buttons; keep the buttons as a fallback | Practice would train execution on the actual rotation, not a click quiz; also removes the answer-click farming path | `practice_ui.lua` scenario cast path + `main.lua` dispatch |
| E5 | **med / low** | Hidden-answer "test mode" toggle for scenario/drills (prompt shows `?`, reveal after the step) | Makes mastery/achievements meaningful; operators who want a guided trainer keep the default | `practice_ui.lua` prompt + `option_tables.lua` |
| E6 | **med / low** | Separate the drill pick from the grade (button selects; a second "Grade" press runs it) | Removes accidental Fs/streak breaks while exploring the panel | `practice_ui.lua:5304-5335` |
| E7 | **med / low** | Per-family drill filtering: hide/disable drills whose grader cannot judge on the running family (`hunter_kill_command` on non-TBC; prepull where no table) | "A button that can only answer UNKNOWN is a trap" (lesson 7); less confusion | `practice_ui.drill_row_sync` + `H.practice_drills` (class publishes `families`) |
| E8 | **med / med** | Class-activation v2: make it an explicit "practice/preview class" selector, or load the selected class's guide/HUD only when it matches the played class; show the active scope on the Progress page | The current option is confusing and looks broken; this makes the intent honest without pretending another class's spell ids work on your character | `option_tables.lua:233`, `main.lua:747-792`, `practice_progress_ui.lua:202` |
| E9 | **med / low** | Surface the weave-progress state (or remove the toggle): a small numeric/alongside-bar meter if E1 is not taken | Today the toggle promises tracking with "no visible change"; users will report it as broken | `option_tables.lua:4634` + `hunter_ui.lua` |
| E10 | **med / low** | Paladin rotation-label parity: publish `get_rotation_key` (or move the paladin's `rotation_names` into the shared label) | The shared rotation label hides on the paladin because `RT.provider` requires `get_rotation_key` (`rotationtext.lua:192-198`); every other class has it | `classes/paladin.lua` + `rotationtext.lua` (no shared edit needed) |
| E11 | **med / med** | Publish `panel.upcoming` per class from real cooldowns/swing (not the synthetic cadence) | Makes the new strip truthful — "next action in 1.2 s" instead of a cadence preview | `practice.lua` harness + each class provider |
| E12 | **low / low** | A "feature status" line in `/st diag`: range helper on/off, HUD template, guide enabled, weave bar on, active vs played class | One paste answers "why is X missing" and would have exposed the activation split immediately | `diag.lua` + `main.lua` |

## 9. Verification performed / UNVERIFIED

**Run at snapshot (read-only):**

- `lua5.1 tests/smoke.lua` — 232 checks, 0 failures.
- `lua5.1 tests/wiring_check.lua` — 873 checks, 0 failures, 3 accepted, 0 stale.
- Class/engine suites: hunter_state 1824/0, hunter_guide_state 1976/0,
  hunter_window_state 213/0, shaman_state 1083/0, shaman_guide_state 1570/0,
  druid_state 1621/0, druid_guide_state 95944/0, warrior_state 2098/0,
  warrior_guide_state 2040/0, rogue_state 1134/0, rogue_guide_state 921/0,
  nextaction_state 631/0, practice_state 1582/0, practice_progress_state 494/0,
  practice_progress_ui_state 290/0, practice_stats_state 558/0, class_activation_state 70/0.
- `practice_ui_state` — 2608/0 at the final snapshot (10 failures while the playhead wave
  was mid-landing; §0).

**UNVERIFIED (needs the client / another lane):**

1. Any in-client behaviour of the fixes above — this audit is static.
2. `IsSpellInRange(56641, "target")`'s exact return (nil vs 0) on Era/SoD; the defect (an id
   absent from the 1.15.9 data) is proven, the API shape is not.
3. Whether the Sniper range buff exists on the operator's Forever client and what aura id it
   carries (F8).
4. Actual CPU cost of the hunter aura walks (call-count proof only; no profiler run).
5. The in-flight hunter bar work (mtime 12:50) and the playhead lane — both moving during
   this audit; re-verify their final state before acting on §1/§5/§8.
6. TBC/Wrath/Forever spell-id correctness beyond the tables' own citations (not re-scraped
   here); Cata/Mists are unsupported and not audited.

## Appendix — evidence commands

```
lua5.1 tests/practice_ui_state.lua | tail -1                # PASS 2608 at final snapshot
lua5.1 tests/wiring_check.lua | tail -1                    # 873 / 0 / 3 accepted
grep -c '^56641;' /home/sam/wow.export/Spell.csv           # 0
grep -m1 '^409957;' /home/sam/wow.export/Spell.csv         # "Gain the Steady Shot ability:"
grep -n 'hunter_weave_prog' classes/hunter.lua             # writes only; no reader
grep -rn 'ST\[.*active_class.*\]' --include=*.lua .        # none unguarded
```
