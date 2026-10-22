# bench/paladin_practice_contract_2026-10-19.md — paladin practice contract + class-side feature closure

Desk: `paladin-practice-contract` (subagent lane). Date: 2026-10-19.
Scope (fixed by the orchestrator): `classes/paladin.lua`, `nextaction.lua`,
`tests/paladin_state.lua`, `tests/nextaction_state.lua`. Nothing else was
touched; no git command was run.
Spec read first: `bench/class_features_drills_2026-10-19.md` §2 (PALADIN:
feature checklist A, drill inventory B, target drill set C, target rotation
scenario D).
Validation owner: **orchestrator**. In-client behaviour is UNCONFIRMED
throughout; sim-match is not client proof.

---

## 0. What this lane delivers

The class side of the practice rotation work, exactly as the orchestrator's
interface contract fixes it:

| Member | Where | Shape |
|---|---|---|
| `ST.PALADIN.practice_rotation` | `classes/paladin.lua:4105` | `{ { action = "<key>", label = "...", orders = { ... } }, ... }` — one entry per action, in the order the rotations name them |
| `ST.PALADIN.practice_scenario_step(self, ctx)` | `classes/paladin.lua:4717` | `{ action = "<key>", reason = "<short text>" }` or **nil** |
| `ST.PALADIN.practice_drills` | `classes/paladin.lua:4924` | `{ { key = "<registry key>", label = "...", grade = function(self, ctx) -> "S".."F"\|nil end }, ... }` — three graders |

Extras (additive, documented, ignored by a caller that does not want them):

| Member | Where | Why |
|---|---|---|
| `ST.PALADIN.practice_orders` | `classes/paladin.lua:4065` | the per-order priority tables (the twist order + the engine's five FCFS tables, by reference) |
| `ST.PALADIN.practice_rotation_for(order_id)` | `classes/paladin.lua:4109` | one order's rotation in its own priority (nil for an unknown order) |
| `ST.PALADIN.practice_action_aliases` | `classes/paladin.lua:4009` | every spelling the shared engine or the practice sim may report → the canonical key |
| `ST.PALADIN.practice_decision(self, ctx)` | `classes/paladin.lua:4680` | the richer answer (action, reason, hold, judge, mode) for a caller that wants the illegal-cast rule |
| `ST.PALADIN.practice_context(self, now, last_action)` | `classes/paladin.lua:5028` | an adapter that builds the context from the shipped practice sim's own state |
| `ST.PALADIN.practice_scenario_key` | `classes/paladin.lua:4130` | `"paladin_rotation"` — the spec's S-P key (§2 D) |
| `st.nextaction.FCFS_ORDERS` / `st.nextaction.fcfs_order(mode)` | `nextaction.lua:969` / `:977` | the engine's five priority tables, published so no caller copies them (a copy would drift from the engine) |

**Nothing here registers itself.** No `H.register_scenario`, no options, no
TOC, no version, no UI. The shared engine (practice.lua / practice_ui.lua,
sibling lanes) looks the three members up by `player_class`
(`ST[player_class]` — the pattern `nextaction_ui.lua:135` and
`practice_ui.lua:550` already use).

---

## 1. The decision source: the guide's own engine

Every decision comes from the same pure engine the next-action guide uses:

- `st.nextaction.evaluate` (the twist tree: Era / TBC / Forever) and
  `st.nextaction.evaluate_fcfs` (the FCFS families: Wrath + the four SoD
  modes) — `nextaction.lua:440` and `:1184`.
- The provider is selected the way the live gather selects it
  (`classes/paladin.lua:3320`): `fcfs_mode` set → the FCFS engine, otherwise
  the twist tree. The practice context may name the mode; the family default
  is Wrath → `"wrath"`, SoD runes → `"sod"` (Exodin, the shipped default), every
  other family → the twist tree.
- The FCFS mode's *order* is never copied: `practice_orders` holds the engine's
  own tables by reference, so the drill and the rotation table cannot drift
  from the engine.

**Action key space** (canonical; the aliases table maps every other spelling
onto it):

```
soc  Seal of Command        sob  Seal of Blood / Martyr    sotc Seal of the Crusader
twist the twist cue         cs   Crusader Strike            judge Judgement
ds   Divine Storm           cons Consecration              exo  Exorcism
how  Hammer of Wrath        hw   Holy Wrath                 hs   Holy Shock (shockadin)
am   Aura Mastery (shockadin)
```

The guide's wire channels are mapped onto it: the FCFS engine's `sob` channel
carries **Divine Storm** (`nextaction.lua:934` — "the sob slot carries the DS
texture on FCFS families"; the mapping itself at `:1337`), and its `how`
filler is **Holy Wrath** on Wrath but **Hammer of Wrath** on SoD
(`nextaction.lua:1343`). Both are spell-level keys here, which is why the
space carries `ds` and `hw` next to the guide's `how`.

### The two contract decisions (and why)

1. **A HOLD / RIDE returns nil.** The rotation wanting nothing pressed is not
   an action, and inventing one would punish a correct pause. The engine
   grades "unknown" — the safe direction. `practice_decision` exposes the
   `hold` flag so a caller that wants the spec's "a cast when out.hold was
   true = an illegal cast" rule can implement it.
2. **The canonical key space is the guide's, not the sim's.** The practice sim
   spells Consecration `consec`; the spec's key space (§2 D-P1) spells it
   `cons`. `practice_action_aliases` maps `consec` → `cons` (and every other
   spelling) and the graders normalise **both** sides before comparing, so a
   shared engine that reports the sim's spelling still grades correctly.

---

## 2. The three drills (spec §2 C)

| Drill | Key | What it grades | Expected action |
|---|---|---|---|
| D-P1 the FCFS order | `paladin_fcfs_priority` | the rotation **priority order** (a mis-pick is a mis-order, not a late pick) | the engine's answer — for the FCFS families that IS the frozen order's first ready entry (the never-wait rule) |
| D-P2 the opener | `paladin_prepull` | the **prepull seal** and the lead | the due seal (`ctx.seal_due`, else the rotation's own table) |
| D-P3 the Judgement decision | `paladin_judge_fit` | whether Judgement is worth the GCD, given the seal state and the time to the next swing | the guide's own Judgement cue (`out.judge_call`) |

Bands (all **[DESIGN]** per the spec — addon policy, deliberately not
sim-sourced):

- **D-P1** `bench/class_features_drills_2026-10-19.md` §2 D-P1: S = no
  mis-pick · A = 1 · B = 2 · C = 3 · D = 4-5 · F = more than 5. Over the
  spec's ten-decision sample the bands land exactly on that table; between
  decisions the band is the running grade.
- **D-P2** §2 D-P2: S = the due seal was up and cast inside the lead · A =
  ≤0.5 s late · B = ≤1.0 s · C = ≤1.5 s · D = up only after the pull · F =
  the wrong seal / no seal.
- **D-P3** §2 D-P3: S = the verdict matched and the press was inside the
  window · A/B/C = the verdict matched but late by ≤1 GCD (split in thirds:
  A ≤ G/3, B ≤ 2G/3, C ≤ G) · D = late by >1 GCD · F = the wrong verdict.

**nil is the answer whenever the drill cannot judge** — never a wrong grade:
an unreadable context, an unknown Judgement cooldown (the verdict would be
fiction), a context that reports no press, a rotation that wants nothing
pressed.

The drill counters live **beside** the engine, not inside it: a weak-keyed
table keyed by the session (`ctx.session` / `ctx.session_id` / the session
object), so a finished session's counters disappear with it and the shared
engine's own tables are never written to. A caller that aggregates the
counters itself (`ctx.mistakes` / `ctx.attempts`) keeps that authority.

### The prepull table (the only sim-sourced numbers in the drills)

`PRACTICE_PREPULL` (`classes/paladin.lua:4053`), cited to
`bench/sod_paladin_variants_2026-10-19.md` §1-§6 and
`bench/paladin_rotation_audit_2026-10-19.md` §Era:

| Rotation | Due seal | Lead | Source |
|---|---|---|---|
| twist (classic APL) | Seal of Command | 1.5 s | the classic APL prepulls the primary seal at −1.5 s |
| tbc (tbc-new APL) | Seal of the Crusader 27158r7 | 0 s | the tbc-new APL prepulls SoC 27158r7 + Judgements at 0 s |
| sod (p8-exodin) | Seal of Command | 2.5 s | p8-exodin prepulls the primary seal at −2.5 s |
| sod_shock (p8-shockadin-1h/2h) | Seal of Command | 1.5 s | the shockadin prepulls at −1.5 s |
| sod_wrath (p8-wrath) | Seal of Command | 1.5 s | p8-wrath prepulls at −1.5 s |
| sod_stack (p8-stack) | Seal of Command | 3.0 s | p8-stack prepulls SoC at −3 s (SoM at −1.5 s) |

The SoD *twist* build's −1.5 s prepull is not reachable through the mode
alone (the live gather has no separate twist mode — `classes/paladin.lua:3311`
falls back to Exodin); the context can always name the due seal and the lead
itself (`ctx.seal_due`, `ctx.prepull_lead`).

---

## 3. Class-side feature checklist §2 (A) — what is closed, what is filed

Re-verified against the **current tree** (the spec's checklist was written
before the SoD variants lane landed; several MISSING rows are closed now).

| Row | Feature | Verdict now | Anchor / what is missing |
|---|---|---|---|
| P-05 | SoC scored 7 PPM, white hits only | **FILED (out of scope)** | `twist.lua:64-70` (the proc model) and `twist.lua:103-110` (`detect_twist_attempt` — the attempt arms on any dual-seal swing). The fix lives in `twist.lua`, which this lane does not own |
| P-06 | Twist on SoC rank 1 | **FILED (out of scope)** | the engine half is live (`out.rank1_advice`, `nextaction.lua:851`; the live reader `classes/paladin.lua:3181`); the **slot** needs `nextaction_ui.lua` and the **option** needs the options lane — both out of scope |
| P-09 | SoD seal-stacking variant | **WIRED** (closed by the variants lane) | `nextaction.lua:959` `FCFS_ORDER_SOD_STACK` + the dual timers `classes/paladin.lua:3290-3292` + the Judge dual gate `nextaction.lua:1004` |
| P-10 | SoD Shockadin 1H/2H | **WIRED** (variants lane) | `nextaction.lua:960` `FCFS_ORDER_SOD_SHOCK` + `classes/paladin.lua:3257-3281` (Holy Shock / Aura Mastery / Sunlight / Templar) |
| P-11 | SoD Wrath-like variant | **WIRED** (variants lane) | `nextaction.lua:961` `FCFS_ORDER_SOD_WRATH` + `classes/paladin.lua:3283-3292` (T2 gate, Templar wait, Cons fallback) |
| P-12 | Holy-Power stacks 1226461 + set 1226460 | **WIRED** (variants lane) | the aura scan `classes/paladin.lua:522-530` → the gather `classes/paladin.lua:3270-3271` → the engine gate `nextaction.lua:1024-1027` |
| P-13 | Templar 1226464 / Sunlight 1239543 / Templar stacks 1240574 | **WIRED** (variants lane) | the aura scan `classes/paladin.lua:507-521` → the gather `classes/paladin.lua:3280-3282` |
| P-16 | Judgement stopattack | **FILED (out of scope)** | the engine advisory is live (`nextaction.lua:841`) and the frame renders STOP; the **macro** half cannot exist (an addon cannot cast) — nothing to build |
| P-17 | Prepull the primary seal | **FILED (out of scope)** | the engine half is live (`nextaction.lua:388` `PREPULL_SEAL_LEAD_SECONDS`, `:845` `out.prepull_ready`); the **pull-timer source** lives in `main.lua` (out of scope). The *drill* half is built now (§2 D-P2 above) |
| P-22 | TBC mana-sustain governor | **FILED (out of scope)** | the read path is live (`classes/paladin.lua:3173-3177`, `nextaction.lua:549`); the **value** needs an options widget + default (options lane) |
| P-24 | Forever Echo of Command / Echo of Righteousness | **FILED (needs ids)** | the model is wired (`classes/paladin.lua:3066-3071`) but the id tables are **deliberately empty** (`classes/paladin.lua:99-105`) until `GetSpellInfo` confirms the ranks in-client. Nothing to invent |
| P-25 | Forever Holy Strike | **FILED (needs an id)** | no sourced id exists (the spec's U-12); the discipline is documented at `nextaction.lua:127` and stays unprobed |
| P-29 | Wrath 2pc-T10 DS reset as DS readiness | **FILED (needs a probe)** | handled by design (post-2pc DS resets surface as `ds_remaining` readiness, so the walk elevates DS automatically; the order is unchanged) — `nextaction.lua:900-903`. Explicit set-bonus detection needs a set id + an equipment probe (no offline-testable probe in scope) |
| P-30 | SoD strictSequence twist (wait the swing out) | **FILED (out of scope)** | the engine half is live (`nextaction.lua:854` `out.hard_wait`) and the provider feeds it (`classes/paladin.lua:3328`); the **render** belongs to `nextaction_ui.lua` |

All other §2 (A) rows (P-01..P-04, P-07, P-08, P-14, P-15, P-18..P-21, P-23,
P-26..P-28, P-31) were WIRED before this lane and are untouched by it.

**Nothing was left unclosed that this lane could close.** Every remaining row
needs a file this lane does not own (`nextaction_ui.lua`, `option_tables.lua`,
`config_presets.lua`, `main.lua`, `twist.lua`), a new spell id, or a new
probe — and the rules say: file it with the reason, never invent.

### What the contract itself closes

The practice contract makes the **rotation teachable**: the six rotation
orders (twist, Wrath FCFS, Exodin, seal-stacking, shockadin, wrath-like) are
now one published table with their priorities, and every one of them is
reachable through the same decision path the guide uses. Before this lane the
SoD variants existed only as guide internals.

---

## 4. UNCONFIRMED ledger (carried, nothing new invented)

| # | Item | Where it bites | Source of the doubt |
|---|---|---|---|
| U-11a | Every SoD variant's in-client behaviour (the Holy-Power read, the Templar wait, the dual-seal timers, the set/item gates) | §2 D-P1/D-P3, the rotation table | the aura ids are APL-cited (`bench/sod_paladin_variants_2026-10-19.md` §0) but **client-unconfirmed**; the practice step withholds them when the context does not carry them |
| U-11b | The SoD variant **selection** in a practice session | the FCFS mode | the live gather picks the variant from live build signals (the Holy Shock spell book, the T2 aura, the dual seals); a practice session carries none of those, so the mode defaults to Exodin unless the context names another (`ctx.fcfs_mode`) |
| U-12 | Forever Holy Strike id | the rotation table's `hw`/`how` rows | no sourced id (the spec's U-12) — the key exists, the spell does not |
| U-14 | Every in-client behaviour of every number here | everywhere | sim-match is not client proof (the standing note in every audit) |
| U-15 | Every grading band in §2 | the three drills | **[DESIGN]** — addon policy, deliberately not sim-sourced |
| U-16 (new) | The practice sim's mana model | the fillers (`cons`, `exo`) | the shipped sim has **no** mana clock; the scenario runs a mana budget instead (§4.4 of the spec). The fillers are gated on `resources.mana_pct`, so a session that does not supply one never prompts a filler — the safe direction, but the caller must supply the budget to teach the fillers |

---

## 5. The context the shared engine has to feed

`{ now, last_action, resources, cooldowns }` is the contract's minimum. The
class side reads more, all **optional**, all through a tolerant alias list; a
missing field degrades to "unknown" (the answer is nil), never to a wrong
grade.

| Field | Used for | Without it |
|---|---|---|
| `now` | the clock | the timing cannot be read → the step answers nil |
| `last_action` | the player's press (any spelling) | the drills answer nil (no press reported) |
| `resources.mana_pct` | the filler gates | the fillers never prompt |
| `cooldowns.<key>` | the readiness of every button | the FCFS order has nothing ready → nil |
| `swing_remaining` (or `session.swing_ends_at`) | the twist tree's landmarks | the twist tree cannot decide → nil |
| `gcd_remaining` (or `session.gcd_expires`) | readiness | the engine's own default (0 = ready) |
| `speed` / `gcd_duration` | the landmarks | the engine's own defaults (3.0 / 1.5) |
| `seal` (or `session.active_seals`) | the seal state | the seal cannot be read → nil |
| `fcfs_mode` | which rotation to teach | the family default (Wrath → wrath, SoD → sod, else the twist tree) |
| `cs_known` | Era has no Crusader Strike | the client's own spell book (`classes/paladin.lua:3101`) |
| `pull_in_seconds` / `seal_due` / `prepull_lead` | the prepull drill | the rotation's own prepull table (§2 above) |
| `cue_at` | the D-P3 lateness | the verdict is graded, the lateness is not |
| `session` / `session_id` | the drill counters' key | the single decision is graded (correct → S, wrong → F) |
| `mistakes` / `attempts` | the engine's own counters | the class-side counters |

`ST.PALADIN.practice_context(sim, now, last_action)` builds that context from
the **shipped practice sim's** own state (the swing clock, the GCD clock, the
weapon speed, the cooldowns, the active seals) — the shared engine may use it
or build its own.

---

## 6. Validation

**Suites (offline, this lane's own):**

- `tests/nextaction_state.lua` — 613 checks, PASS (the new pins: the five
  published FCFS tables, their exact orders, and the `fcfs_order` accessor).
- `tests/paladin_state.lua` — 643 checks, PASS (the new pins: the rotation
  table and its per-order views, the scenario step's decisions and its
  refusals, the three graders and their bands, the context adapter).

**Full harness** (`bash tests/run.sh`): **41 steps, 3 failed** at the time of
writing — and every red is the **shared practice-registry lane's in-flight
crossfire**, not this lane:

| red | what it says | why it is not this lane |
|---|---|---|
| `tests/druid_state.lua` | "the registry carries druid_powershift" | the registry entry is **commented out** in `practice.lua:2399` right now (the registry lane is moving it) |
| `tests/warrior_state.lua` | "W6 drill: exactly one scenario is registered for WARRIOR" | the same: `practice.lua:2240` is commented out |
| `tests/shaman_state.lua` | "the scenario key resolves through the registry" (+ three drill pins) | the same: `practice.lua:2499` is commented out |

(An earlier run also showed `tests/hunter_guide_state.lua` red with two pins
in the hunter lane's own files; that lane has since settled its own. The
hunter suites load `compat.lua`, `utils.lua`, `hunter_window.lua`,
`hunter_ui.lua`, `classes/hunter.lua`, `hunter_guide.lua` — **not**
`nextaction.lua`, **not** `classes/paladin.lua`.)

`practice.lua` is a sibling lane's file; this lane never touched it. The
paladin, nextaction, guide-contract, practice-progress, practice-ui, hud,
bars and wiring suites are green, and the druid/warrior/shaman suites fail
only on the registry pins their own lane owns.

**luacheck:** `Total: 2 warnings / 0 errors in 82 files` — the standing floor
(`compat.lua:36` + `main.lua`, both pre-existing and sibling-owned). The four
files this lane touched are **0 warnings / 0 errors**.

**Mutations** (disposable copies under `/tmp/opencode/pal_mutation`, the repo
tree never touched): **12/12 killed**.

| # | Mutation | Caught by |
|---|---|---|
| M1 | the Wrath FCFS order loses its head | `nextaction_state` (the order table) + the existing wrath pins |
| M2 | the Exodin order is not published | `nextaction_state` (the five-orders pin) |
| M3 | the twist order loses the twist | `paladin_state` (the rotation table carries `twist`) |
| M4 | the twist cue answers the wrong key | `paladin_state` (the step cues `twist`) |
| M5 | the step answers on a hold | `paladin_state` (the idle FCFS tick answers nil) |
| M6 | the priority drill never counts a miss | `paladin_state` (the mis-pick grades F) |
| M7 | the prepull band shifts | `paladin_state` (the early seal grades S) |
| M8 | the judge drill ignores the verdict | `paladin_state` (the wrong verdict grades F) |
| M9 | the context adapter loses the swing clock | `paladin_state` (the adapter reads the clock) |
| M10 | the seal always reads "none" | `paladin_state` (the session's Blood seal carries the Judgement cue) |
| M11 | an unknown Judgement cooldown reads ready | `paladin_state` (an unknown cooldown never cues a judgement) |
| M12 | the prepull drill ignores the wrong seal | `paladin_state` (the wrong seal grades F) |

**Runtime probe on the shipped sim** (offline, `/tmp/opencode/pal_engine_probe.lua`):
the real `st.practice` sim is driven for 400 ticks while the contract is asked
at every tick and the player presses what it says. The sequence that comes
out is the rotation itself — Crusader Strike → the Judgement cue → the Blood
seal twist work — and the priority drill grades every decision S. This is an
offline probe (no client), but it is the real sim and the real engine.

**Not validated by this lane** (honest limits): nothing was run in a game
client; the SoD variant inputs, the prepull leads and the grading bands are
unproven in-client; the shared engine's exact call shape (how it builds the
context, when it calls the graders) is a coordination assumption, documented
in §5 rather than observed.

---

## 7. Open items for the shared engine lane (not blockers)

1. Register the scenario under `ST.PALADIN.practice_scenario_key`
   (`"paladin_rotation"`) and the three drills under their keys
   (`paladin_fcfs_priority`, `paladin_prepull`, `paladin_judge_fit`).
2. Normalise the player's press through
   `ST.PALADIN.practice_action_aliases` (the sim spells Consecration
   `consec`; the canonical key is `cons`) — or compare against the canonical
   keys only.
3. Feed the context: at minimum `now`, `cooldowns` and the swing/GCD clocks
   (§5). `ST.PALADIN.practice_context(sim, now, last_action)` does it from
   the shipped sim.
4. If the engine wants the "a cast during a hold is an illegal cast" rule,
   read `ST.PALADIN.practice_decision(...).hold` (the contract's step returns
   nil for a hold by design).
5. The SoD variant drills need the build's own signals (`holy_power_stacks`,
   `sod_dual_seal_active`, the set gates) in the context; without them the
   engine withholds them (unknown-hides) and the scenario teaches Exodin.
