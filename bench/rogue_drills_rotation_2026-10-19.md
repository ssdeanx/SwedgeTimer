# rogue_drills_rotation_2026-10-19 — rogue rotation scenario, target drill set, class-side gap closure

Desk: `rogue-drills`. Spec: `bench/class_features_drills_2026-10-19.md` §2.4 (the rogue
section: A checklist, B drill inventory, C target drill set, D target rotation scenario).
Validation owner: **orchestrator**.

Scope (the only files touched): `classes/rogue.lua`, `rogue_guide.lua`,
`tests/rogue_state.lua`, `tests/rogue_guide_state.lua`. No `practice.lua` /
`practice_ui.lua` / options / config / other classes / `main.lua` / `compat.lua` /
`hud.lua` / `bars.lua` / `run.sh` / TOCs / versions / README / CHANGELOG / docs.
No git, no lint-config changes.

---

## 1. What ships (the orchestrator's fixed contract)

### 1.1 `ST.ROGUE.practice_rotation` — the rotation table

`classes/rogue.lua` — twelve entries in the engine's rule order. Each entry carries
the house fields the shared engine reads (`action`, `label`) plus the citation and the
family set:

| # | action | label | rule | source cited in the entry |
|---|---|---|---|---|
| 1 | `expose` | Expose Armor | 1 | classic `combat_sinister_strike_iea.apl.json` (EA 11198 at 5CP, remains ≤ 3 s); tbc-new `swords.apl.json` (the Expose group) |
| 2 | `snd` | Slice and Dice | 1b | wotlk `combat.apl.json` (auraRemainingTime(SnD) ≤ 1 s); tbc-new/classic `slice_and_dice.go` (per-CP 9/12/15/18/21 s); sod `P5_Saber.apl.json` (4+CP) |
| 3 | `hfb` | Hunger for Blood | 1c | wotlk `mutilate.apl.json` (auraRemainingTime(Hunger for Blood) ≤ 1 s → cast) — Wrath only |
| 4 | `shiv` | Shiv | 2 | tbc-new `swords.apl.json` + `shiv.go` (non-Mutilate, below 5CP) |
| 5 | `envenom` | Envenom | 3 | sod `P5_Saber.apl.json` (Envenom-primary 4+CP); wotlk `combat.apl.json` (Envenom 57993 at 4+CP) |
| 6 | `eviscerate` | Eviscerate | 4/5 | classic `combat_sinister_strike.apl.json` (Evisc 31016 at 5CP); wotlk `combat.apl.json` (Evisc 48668 at 4+CP, fight ≤ 4 s) |
| 7 | `rupture` | Rupture | 5 | tbc-new `swords.apl.json` (Rupture-first); wotlk `combat.apl.json` (Rupture 48672 at 4-5CP, SnD ≥ 4 s) |
| 8 | `ar` | Adrenaline Rush | 5b | tbc-new `swords.apl.json` (prepull −1 s; AR at energy ≤ 40); classic (energy < 59 with a tick inside 1 s); forever (≤ 50 with SnD) |
| 9 | `bf` | Blade Flurry | 5c | wotlk `combat.apl.json` (Blade Flurry 13877 while SnD rides); tbc-new; forever |
| 10 | `coldblood` | Cold Blood | 5d | tbc-new `swords.apl.json` (Cold Blood 14177 with SnD); forever (at 5CP) |
| 11 | `tea` | Thistle Tea | 6 | classic `combat_sinisher_strike_sweaty.apl.json` (Tea 7676 at energy ≤ 29 with a tick outside 1 s); tbc-new (≤ 30) |
| 12 | `builder` | Builder | 7 | classic `combat_sinister_strike.apl.json` (Sinister Strike 11294); tbc-new (SS 26864 / Backstab 26863 / Mutilate 34413) |

The order IS the engine's rule order (rogue_guide.lua's header, rules 1..7) — the
audit's "the engine's rule order is the compiled table".

Two optional members the shared engine reads when a class publishes them
(`practice_ui.lua`'s `practice_rotation_entries` / `practice_rotation_family`):

- `ST.ROGUE.practice_rotation_for(family)` — the family's slice. The family sets
  mirror the engine's own gates (SnD/EA/Tea/AR: the four classic families; Shiv:
  ERA+TBC; Cold Blood: TBC+FOREVER; Blade Flurry: the four; Hunger for Blood:
  WRATH; Rupture: the rupture-first families — the Era sims are Eviscerate-only).
  **RETAIL gets an empty slice** (no retail sim — audit R-22), so the scenario is
  never offered there (the audit's §4.6). The SoD token plays the Era slice (the SoD
  rows ride the same action keys).
- `ST.ROGUE.practice_rotation_family()` — "SOD" on the ERA token with the SoD-only
  Envenom rune known (the provider's frozen SoD latch), else the compat family.

### 1.2 `ST.ROGUE.practice_scenario_step(self, ctx)`

Returns `{ action = "<spell key>", reason = "<short text>" }`, or **nil** when the
state cannot decide (the engine grades that step UNKNOWN — it never records a wrong
action and never invents an expectation).

The step is a thin wrapper over the pure `st.rogue_guide.practice_step(ctx)`, which
runs the **same** `evaluate` the guide shows — no verdict is re-implemented.

**A POOL verdict returns nil, not an action.** The audit's S-R wants "a press while
the verdict is POOL" to count as an illegal cast, but the shipped engine can only
compare an *expected action string* (`H.rotation_run_decide`): a nil expected reads
as UNKNOWN (no attempt), and a mismatched expected/actual reads as out_of_order (F).
A "pool" action key would make every POOL step an automatic F (the panel has no
"pool" button, and doing nothing is graded a "miss" → F). The other class lanes
made the same call (`shaman_guide.practice_step` returns nil on a hold; the paladin
returns nil when there is no action). **Filed for the operator** (§5, HU-8): either
the engine grows an "expected = hold" concept, or the audit's rule is amended.

### 1.3 The ctx contract (for the sibling lane that registers the drills)

```
ctx.now          the clock (the engine's injected domain)
ctx.last_action  the action the player cast last (nil at the start of a run)
ctx.resources    the state bag (the engine's own frozen input names)
ctx.cooldowns    { <action key> = <seconds remaining> }   (0 = ready)
```

The class publishes its own ctx builder — `ST.ROGUE.practice_context(self, now,
last_action)` — so the step and the drills read the **class's own gathered guide
inputs** (the live state the guide shows) instead of the engine's fallback (which
carries only a few resource keys). The state bag therefore holds the engine's
frozen input names: `energy_now` (alias `energy`), `energy_tick_in` (alias
`tick_in`), `max_energy`, `cp`, `ttd`, `rupture_remains`, `rupture_refresh`,
`rupture_min_ttd`, `finisher_min_cp`, `deadly_stacks`, `deadly_remaining`,
`envenom_buff_remains`, `ea_duty`, `ea_remains`, `ea_refresh`, `sod_envenom`,
`snd_usable`, `snd_remains`, `snd_refresh`, `snd_min_cp`, `ar_ready`, `bf_ready`,
`coldblood_ready`, `shiv_ready`, `shiv_refresh`, `mutilate_known`, `tea_ready`,
`tea_energy_max`, `hfb_usable`, `hfb_remains`, `hfb_refresh`, `pool_pre`,
`pool_post`, `inputs_unknown`, `family`.

**A missing read stays nil**, so the engine stays silent on that rule
(unknown-hides). A caller that only knows the energy and the combo points gets the
plain finisher/builder decision and never a guessed upkeep prompt. A cooldown row at
0 proves a readiness flag (`ar`/`bf`/`coldblood`/`shiv`/`tea`); a missing row stays
nil. The action under test is read from `ctx.last_action`, with the aliases
`ctx.action` / `ctx.pick` / `ctx.pressed` / `ctx.choice` accepted too.

### 1.4 `ST.ROGUE.practice_drills` — the audit's target drill set (section C)

Four drills, one skill each. **The energy drill is NOT one of them** (the operator's
ruling: `rogue_energy_pool` is baseline resource behaviour). Each entry carries the
house fields (`key`, `label`, `kind`, `description`, `grade`); the graders live in
the pure engine (`rogue_guide.lua`) and the class entries are thin wrappers.

| key | label | kind | what it grades |
|---|---|---|---|
| `rogue_finisher_order` | The finisher order | `rotation_order` | the engine's action vs the pressed action — the upkeep → finisher chain; a near-miss (Rupture instead of Eviscerate on Era) **is** a mis-pick |
| `rogue_cp_finish` | The combo-point decision | `situational` | when to commit a finisher, against the family's own floor |
| `rogue_snd_upkeep` | The debuff upkeep | `rotation_window` | keeping Slice and Dice up (the per-CP window) |
| `rogue_opener` | The opener | `transition` | the prepull and the first-finisher decision (a synthetic pull clock) |

Grade bands — **[DESIGN]** (the audit's §5 U-15: addon policy, not sim-sourced):

- `rogue_finisher_order`: the **run's** mis-pick count — 0 = S, 1 = A, 2 = B, 3 = C,
  5 = D, more = F (the audit's "S = 100 % correct picks, A = ≤ 1 mis-pick in 10, …").
  The counters live beside the engine in a weak-keyed table keyed by the session
  (`ctx.session` / `ctx.session_id` / the session object), so a finished session's
  counters disappear with it; when the engine aggregates the counters itself
  (`ctx.mistakes` / `ctx.attempts`) those win and nothing is stored.
- `rogue_cp_finish`: at/above the floor with the right finisher = S; one CP short = A;
  two = B; at the floor with the wrong finisher = C; below the floor on a **dying**
  target = D (forgiven); below the floor on a healthy target = F (the CP was wasted).
- `rogue_snd_upkeep`: refreshed while the debuff was still up = S; one tick late
  (≤ 2 s) = A; ≤ 4 s = B; the debuff had expired = C; the builder pressed over the
  window = D; down for longer than the debuff's own per-CP length = F.
- `rogue_opener`: the right step on time = S; one GCD late = A; two = B; three = C; the
  step far too late (or a due step skipped) = D; the wrong order = F.

Every grader returns **nil** when it cannot decide (an unreadable state, a press it
cannot classify, a missing clock) — the engine shows UNKNOWN and records no attempt.

Engine helpers that carry the shared data (`rogue_guide.lua`): `snd_duration_for_cp`
(the sourced per-CP rows only), `family_floors` (the per-family finisher/dump/TTD
floors, read from the engine's own tables so a tuning pass moves the drill and the
guide together), `opener_rank` (the opener order for the order/timing split),
`build_practice_inputs` / `practice_expected` / `practice_step` (the ctx → verdict
path).

---

## 2. The class-side feature checklist (§2(A)) — disposition per row

The audit's row verdicts were re-checked against the tree in this session. Three rows
were **stale** (closed by earlier lanes) and one is closed here.

| Row | Audit verdict | Disposition now | Evidence |
|---|---|---|---|
| R-01 SnD upkeep | WIRED (logic) / DEGRADED (display) — "no slot exists" | **CLOSED (stale)** — the display ships: the guide slot `snd` (`classes/rogue.lua`), the HUD slot `snd`, the rotation label names it. The audit's "7 slots, frozen" is stale — the guide ships **11** slots | `classes/rogue.lua` (guide slot `snd`, HUD slot `snd`); `tests/guide_contract.lua:1343` pins 11 icons |
| R-02 per-CP SnD durations | WIRED | WIRED | `rogue_guide.lua` (SND_DURATION_BY_CP + the new `snd_duration_for_cp`) |
| R-03 builder identity | DEGRADED (Hemo excluded) | **FILED** — Hemo's English name is uncertain (U-04: a wrong name never resolves, so the exclusion is safe) and the APL's CP/stack/rune gating needs a rune/stack model the addon does not carry | the builder chain in `classes/rogue.lua`; audit U-04 |
| R-04/R-05/R-06 finisher spine, CP floors, dump floors | WIRED | WIRED | `rogue_guide.lua` (FINISHER_MODES / FINISHER_MIN_CP_BY_FAMILY / DUMP_MIN_CP_BY_FAMILY) |
| R-07 pool lines | WIRED | WIRED | `rogue_guide.lua` (POOL_BANDS) |
| R-08 EA windows | WIRED | WIRED | `rogue_guide.lua` (EA_REFRESH_BY_FAMILY) |
| R-09 Forever EA finisher lockout | DEGRADED — "the explicit lockout … is filed" | **CLOSED (stale)** — the H6 lane shipped it: `EA_LOCKOUT_FAMILIES` + `ea_lockout_active`, wired into evaluate (it suppresses snd / the dump / the planned finisher / Cold Blood) | `rogue_guide.lua:422,934` |
| R-10 Rupture recast-when-missing | WIRED | WIRED | `rogue_guide.lua` (RUPTURE_REFRESH_BY_FAMILY) |
| R-11 Rupture per-CP durations | DEGRADED (data ships, no rule consumes it) | **FILED** — only the 1CP (8 s) and 5CP (16 s) rows are sim-sourced; consuming them per-CP would leave 2-4CP on the flat floor (a discontinuity the data cannot justify), and the same `min_ttd` value also drives the dying-target dump rule, so a per-CP table would move the dump threshold too. Needs the remaining rows (or a split `min_ttd`) first | `rogue_guide.lua:348,662`; audit U-05 |
| R-12 Thistle Tea | WIRED / DEGRADED (Eureka + SoD lines filed) | **CLOSED in part (stale)** — the SoD 10/40 line is reachable now: the SoD latch landed (`classes/rogue.lua` — `inputs.sod_envenom` / `rogue_is_sod`) and the SOD rows ride it. **FILED**: the Eureka-25 line (the in-client Eureka probe 1259812 is CLIENT-UNCONFIRMED). **CORRECTED 2026-10-20** (desk `corpus-corrections`): the id's **name** is now settled — 1259812 = **"Gnome Eureka"** on the Forever client (the rogue APL's own variable) — but the **client** source is still absent, so the line stays filed | `rogue_guide.lua:432,443`; `classes/rogue.lua` (the SoD latch) |
| R-13/R-14/R-15 AR, Blade Flurry, Cold Blood | WIRED (slot-less) | WIRED | `rogue_guide.lua` (AR_ENERGY_MAX_BY_FAMILY / BF_FAMILIES / CB_FAMILIES) |
| R-16 Shiv EA-context check | DEGRADED | **FILED** — needs the APL-literal EA-window design (the family's minimum-EA and Shiv-context windows are not modelled); the family gate, the Mutilate gate and the CP gate already ship | `rogue_guide.lua:467,475,478` |
| R-17 energy-tick model | WIRED | WIRED | `classes/rogue.lua:94,95,105` |
| R-18 SoD Envenom-primary | DEGRADED / MISSING — "unreachable until SoD detection lands" | **CLOSED in part (stale)** — the SoD latch landed, so `ENVENOM_RULES.SOD` is reachable (ERA + `sod_envenom == true`). **FILED**: Poisoned Knife 425012 (the id needs in-client confirmation), the Vanish→Envenom sequence, Cut to the Chase | `rogue_guide.lua:497,503` |
| **R-19 Wrath sin triad** | MISSING | **CLOSED IN PART (this lane)** — the Hunger for Blood upkeep now ships (see §3). **FILED**: the Cut-to-the-Chase / Rupture-anchored SnD refresh (the APL's third SnD entry needs the **fight's remaining time**, which the guide inputs do not carry — only the practice session has a fight clock) and Vanish → Overkill (needs a guide slot + the prepull context the guide does not have) | see §3 |
| R-20 Tricks / Killing Spree / Riposte | MISSING | **FILED** — every one of them needs a guide slot (the slot contract is frozen: `tests/guide_contract.lua:1343` pins the rogue's 11 icons) plus APL-literal design. **The audit's ids are also wrong** — see §4 | `rogue_guide.lua:1102-1105` (the Cold Blood gate comment already names the filing) |
| R-21 Sweaty 0.5 s widening | DEGRADED | **FILED** — the widening needs in-client proof (the audit's own direction); the ≥ 79 energy override ships | `rogue_guide.lua:458` |
| R-22 Retail sim verification | UNCONFIRMED | **FILED** — no retail sim repo in the brief set; the retail rows stay guide-sourced and UNCONFIRMED (the rotation's retail slice is empty) | audit §6 |

---

## 3. What was closed in code: the Wrath Hunger for Blood upkeep (R-19, part)

**The sim source (fetched live 2026-10-19, not from memory):**
`https://raw.githubusercontent.com/wowsims/wotlk/master/ui/rogue/apls/mutilate.apl.json`
— the third priority entry:

```json
{"action":{"condition":{"cmp":{"op":"OpLe","lhs":{"auraRemainingTime":{"auraId":{"spellId":51662}}},"rhs":{"const":{"val":"1s"}}}},"castSpell":{"spellId":{"spellId":51662}}}}
```

i.e. **refresh Hunger for Blood when its aura has ≤ 1 s left**, right after the two
Slice-and-Dice entries (so the upkeep order is SnD → HfB, as the engine now has it).

**What ships:**

- `rogue_guide.lua` — `HFB_FAMILIES` (WRATH only), `HFB_REFRESH_BY_FAMILY` (1 s, the
  sim's line), `HFB_REFRESH_DEFAULT`, and the pure verdict `hfb_verdict(family, args)`
  (the Slice-and-Dice shape: a missing buff is an upkeep gap, an unreadable clock
  hides, a family without a row never prompts).
- `rogue_guide.lua` — rule **1c** in `evaluate`, between the SnD upkeep (1b) and the
  Shiv upkeep (2) — the APL's own order. It yields to the 1a hold, to the Forever
  lockout and to the dying-target skip (the SnD rule's shape).
- `classes/rogue.lua` — the provider gather: the spell resolves through the client's
  **own** spell data by its English name (`"Hunger for Blood"`), the talent gate is a
  strict `is_spell_known == true`, and the buff clock is the player's own aura. **No id
  is shipped** — the sim's 51662 is sim-side evidence only (the remembered-id rule).
- `classes/rogue.lua` — the rotation label names the slot-less action
  (`ACTION_FALLBACK_NAMES.hfb`), and the rotation table carries the step (WRATH only).

**No default-visible change outside Wrath:** the rule is family-gated (Era/TBC/Forever
never prompt) and talent-gated (a player without Hunger for Blood never prompts), and
the M6 secret-regime bit suppresses every verdict while the auras are unreadable.
There is **no twelfth guide slot** — the slot contract is frozen, so the upkeep rides
the rotation label exactly like the other slot-less actions (a filed follow-up below).

---

## 4. Citation corrections found while re-checking the audit (no code impact)

The audit's §2(A) rows R-19/R-20 quote ids that do not survive a live look at the
wowsims wotlk APLs (fetched 2026-10-19). **No id reaches our tables** (the addon
resolves every spell by name), so this is a documentation correction, not a code fix:

| the audit says | the live APL shows | source |
|---|---|---|
| "Cut to the Chase **57934**" (R-19) | **57934 is Tricks** (cast at energy ≤ 50). Cut to the Chase has no id in the APLs this lane touched | wotlk `combat.apl.json`, `mutilate.apl.json` |
| "Killing Spree (51690) at energy ≤ 50" (R-20 / audit F3) | Killing Spree is **54758** (cast while Blade Flurry rides or is within 8 s of ready); **51690** is a separate energy ≤ 50 cast in the same list | wotlk `combat.apl.json` |
| "Hunger for Blood (51662) at ≤ 1 s" (R-19 / W-G1) | **confirmed verbatim** | wotlk `mutilate.apl.json` |
| "Vanish (26889) mid-fight when Overkill (58426) absent" (W-G1) | **confirmed verbatim** (Overkill is the prepull aura at −1 s) | wotlk `mutilate.apl.json` |
| "TBC prepull AR (−1 s) and AR at energy ≤ 40" (audit F3) | **confirmed** (the TBC prepull lead is the `PREPULL_LEAD_SECONDS = 1` this lane ships) | audit F3 / tbc-new `swords.apl.json` |

---

## 5. Filed follow-ups (with the reason each one is not wired here)

1. **A twelfth guide slot for the Hunger for Blood upkeep** — the guide slot contract
   is frozen and `tests/guide_contract.lua:1343` pins the rogue's 11 icons (that file
   is out of this lane's scope). The upkeep rides the rotation label meanwhile; the
   HUD could carry it as an aura row the same way it carries SnD.
2. **The Cut-to-the-Chase / Rupture-anchored SnD refresh** (the wotlk `combat.apl.json`
   third SnD entry: refresh SnD when it would fall before the Rupture dot does) — the
   APL's guard also needs the **fight's remaining time**, which the guide inputs do not
   carry (only the practice session has a fight clock). Half a rule is worse than none.
3. **Vanish → Overkill** (the wotlk mid-fight Vanish while Overkill is not active, plus
   the Overkill prepull) — needs a guide slot and the prepull context the guide does
   not have; the practice opener drill carries a synthetic prepull instead.
4. **Tricks / Killing Spree / Riposte prompts** (R-20) — guide slots + APL-literal
   design; the ids in the audit row are also wrong (§4).
5. **The Rupture per-CP duration table** (R-11) — the 2-4CP rows are UNCONFIRMED and
   the shared `min_ttd` also drives the dump rule (§2, R-11).
6. **The Shiv EA-context check** (R-16), the **Hemo builder** (R-03), the
   **Eureka-25 Tea line** (R-12), the **sweaty 0.5 s widening** (R-21), the **Poisoned
   Knife / Vanish→Envenom / CttC SoD rows** (R-18) and the **retail sim verification**
   (R-22) — each needs its own sourced input (an in-client probe or a sim row this
   lane does not have); the reasons are in §2.
7. **The POOL verdict as an illegal cast** (the audit's S-R) — the shipped engine's
   `H.rotation_run_decide` compares two strings; a nil expected reads as UNKNOWN and
   a mismatched expected/actual reads as out_of_order (F). There is no "expected =
   hold" in the engine's vocabulary, and every class lane (shaman, paladin, rogue)
   answers a hold with nil. **Raised for the operator** (hands-up): either the engine
   grows a hold concept, or the audit's rule is amended to "the hold is ungraded".

---

## 6. Validation

- `lua5.1 tests/rogue_state.lua` → **787 checks, 0 failures** (incl. the end-to-end
  seam: the shared harness finds the rogue's drills and scenario step by
  `player_class` and drives both).
- `lua5.1 tests/rogue_guide_state.lua` → **756 checks, 0 failures**.
- `luacheck .` → **2 warnings / 0 errors** (the floor; both KEEP-ruled — the two are
  in `compat.lua` and `main.lua`, not in this lane's files).
- `bash tests/run.sh` → **41 steps, 0 failed** (the whole tree is green at this lane's
  final run; the reds seen during the lane — `tests/hunter_state.lua`,
  `tests/practice_ui_state.lua`, `tests/shaman_state.lua`,
  `tests/shaman_guide_state.lua` — were parallel-lane crossfire: `classes/hunter.lua`,
  `tests/hunter_state.lua`, `classes/druid.lua`, `classes/shaman.lua`,
  `shaman_guide.lua` and `practice_ui.lua` were being rewritten by other lanes while
  this lane ran).
- **Mutation proofs** (`/tmp/opencode/rogue_mutations.sh`, copies in
  `/tmp/opencode/rogue-mut` + `rogue-mut-pristine`): the pristine copy is green and
  **20/20 mutations are killed**:
  1. the HfB family gate widened to Era → killed (the family-gate pins);
  2. the HfB refresh window widened to 5 s → killed (the window pins);
  3. rule 1c removed from `evaluate` → killed;
  4. the rotation table's order broken (SnD before Expose) → killed;
  5. a rotation step's `source` citation dropped → killed;
  6. the scenario step ignores the engine's action → killed;
  7. a POOL hold answers as a cast → killed;
  8. the combo-point floor bands loosened → killed;
  9. the debuff-upkeep late bands loosened → killed;
  10. the opener timing bands loosened → killed;
  11. the per-CP SnD duration guesses an unsourced row → killed;
  12. the family floors lose the dump floor → killed;
  13. the opener order breaks (the upkeep below the builder) → killed;
  14. the class ctx builder drops the upkeep state → killed;
  15. the rotation slice loses the family filter → killed;
  16. the namespace mirror dropped (HU-7) → killed;
  17. the priority drill's verdict inverted → killed;
  18. the cooldown pass wipes the state bag's readiness → killed;
  19. the combo-point drill grades an unknown state instead of nil → killed;
  20. the opener's prepull flag read breaks (a boolean is not a number) → killed.

## 7. Notes for the sibling lane that registers the drills

- Register the scenario under the key `rogue_rotation` and the drills under
  `rogue_finisher_order`, `rogue_cp_finish`, `rogue_snd_upkeep`, `rogue_opener` (the
  audit's §2.4 C names). The class side is registered by the shared engine, not here.
- The class module is reachable under both names: `ST.ROGUE` (the AceAddon table) and
  `st.ROGUE` (the namespace mirror, HU-7). The engine resolves the AceAddon table
  first, so the mirror is belt-and-braces.
- **Call a grader once per graded pick** with `ctx.last_action` = the pressed action
  key (the aliases `action` / `pick` / `pressed` / `choice` also work). The priority
  drill owns its own session counters; when the engine supplies
  `ctx.mistakes` / `ctx.attempts` those win.
- A grader returning nil means "unknown" — do not grade it as a miss.
- The scenario step's POOL verdict is **nil** (a hold is not an action): the step reads
  UNKNOWN and records no attempt (§5, item 7).
- `ctx.resources` should carry the upkeep state (`snd_usable`, `snd_remains`,
  `ea_duty`, `rupture_remains`, `deadly_stacks`, …) — without it the engine stays
  silent on the upkeep rules and the drills can only grade the finisher choice. The
  class publishes `ST.ROGUE.practice_context` for exactly this.
- The opener drill needs a synthetic pull clock (`ctx.pull_at`, or `ctx.pull_in`
  against `ctx.now`); without it the drill grades nil by design.
