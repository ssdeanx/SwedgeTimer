# Paladin scenario surface: F1 (CRITICAL), F6, F8 + the APL layer

Lane: paladin-scenario (2026-10-20). Scope: `classes/paladin.lua`,
`nextaction.lua` (NOT changed — see §5), `tests/paladin_state.lua`,
`tests/guide_contract.lua` (paladin section only).

Source of the findings: the scenario-100 audit (the desk's report was not on the
bench when this lane started; the dispatch brief carried F1/F6/F8) and
`bench/rotation_gap_vs_apl_2026-10-20.md` §6 (the paladin section, the fetched
APL rows per family).

## 1. F1 (CRITICAL) — the paladin's scenario graded nothing in-game

**The defect.** `ST.PALADIN.practice_context` (the class's own ctx builder) was
written for the TWIST SIM: it read `state.swing_ends_at`, `state.gcd_expires`,
`state.effective_speed`, `state.cs_cooldown_expires` and `state.active_seals`.
The shared panel calls it with the ADDON OBJECT as `self`
(`practice_ui.lua:4350` → `module.practice_context(ST, now, last_action)`), and
the addon object carries no sim clock — so every sim-shaped field was nil, the
ctx had no `swing_remaining` and no `gcd_remaining`, `build_practice_inputs`
refused (the "a fiction is worse than an unknown" guard), `practice_decision`
answered nil and **every scenario step was UNKNOWN**: no attempt, no grade, no
XP. The class's own ctx shadowed the shared engine's gather-based fallback
(`practice_ui.lua:4365-4422`), which would have carried the live numbers.

**The fix** (`classes/paladin.lua`, `ST.PALADIN.practice_context`). The builder
now serves TWO shapes:

* the **SIM shape** (the twist sim): the session state's clock, cooldowns and
  seals are copied verbatim — bit-identical to before;
* the **LIVE shape** (the real client): when the sim shape answered no timing,
  the builder falls back to the class's OWN gathered guide inputs — the same
  state the next-action guide reads (`gather_guide_inputs`, `classes/paladin.lua`
  :3133): `swing_remaining`, `gcd_remaining`, `speed`, `G`, the seal, the FCFS
  mode, the cooldown rows and the resource values.

The live values land on the ctx in the contract's own names
(`ST.PALADIN.practice_gathered_flat`); everything the gather produced also rides
in `ctx.resources` (the rogue's rule) and the cooldown rows in `ctx.cooldowns`
(the engine's `<key>_remaining` naming). The gather is pcall-guarded, so a
half-loaded module degrades to UNKNOWN, never to a wrong action. This is the
same discipline the rogue (`classes/rogue.lua:2339`) and the hunter
(`classes/hunter.lua:3553`) already use.

**The pin** (`tests/paladin_state.lua` §25): the REAL builder is driven with
`ST` as `self` and the whole chain is asserted — the ctx carries the timing, the
seal and the cooldown rows; `practice_decision` and `practice_scenario_step`
answer (an action or an explicit hold, never nil); the shared engine's own
grading (`H.practice_scenario_step("PALADIN", ST, ctx)`) is NOT UNKNOWN. The
sim shape is pinned beside it: the sim's clock, GCD, seals and speed still come
from the sim (the live fallback must not overwrite them).

## 2. F6 — every rotation row is cited

The rotation table carried no `source` at all (the other five classes cite
every row). Every entry of `ST.PALADIN.practice_rotation` now carries:

| field | meaning |
|---|---|
| `source` | the fetched APL and the position of the row in it (`bench/rotation_gap_vs_apl_2026-10-20.md` §6.2) |
| `note` | what the row is, in one line |
| `families` | the family gate (the clients the row is played on) |
| `ids` | the family's numeric spell id (the APL's rank id — the citation, not a runtime probe) |
| `tbc_name` | the spell's NAME for the TBC family (TBC resolves by name, never by a bare id) |

The ids are family-gated: an id is only valid on a family the row plays, and a
TBC row carries no numeric id (pin: `entry.ids.TBC == nil` and `tbc_name` is a
string — a macro row, the twist, names neither and carries no id at all).

## 3. F8 — the running order's slice is reachable

Two defects, both closed:

* `ST.PALADIN.practice_rotation_for(order_id)` NEEDED an order id, but the
  shared panel calls it argument-free (`practice_ui.lua:819`, "the call is
  argument-free on purpose"). The paladin answered nil, so the panel fell back
  to the guide's slot vocabulary and the paladin never published its rotation.
  The id is now OPTIONAL: an argument-free call answers the RUNNING order's
  slice.
* The three SoD orders (`sod_stack`, `sod_shock`, `sod_wrath`) were
  unreachable in the practice path: only the live gather knows which SoD
  variant the client plays, and the practice ctx never carried its FCFS mode.
  The live gather now PUBLISHES the running order
  (`ST.PALADIN.practice_running_order`, written next to the FCFS mode it
  decided), the ctx carries the mode, and the slice follows. The family default
  (the Wrath FCFS table, the SoD Exodin table, else the twist tree) is the
  fallback when no gather has answered.

The "table must match the shipped surface" rule is met in the direction the
brief names: all SIX shipped orders are reachable and the table's rows are the
shipped orders' rows plus the cited APL rows of §4 — nothing else.

## 4. The APL layer (HU-12's ruling applied)

HU-12 (hands-up, ruled by the orchestrator): the ROTATION TABLE carries the
APL's spell rows; the APL's PRE-PULL rows belong to a per-class prepull table.

**The combat rotation** (`ST.PALADIN.practice_rotation`) now carries the WotLK
APL's two missing rows, family-gated to WRATH and cited:

| row | id | APL position |
|---|---|---|
| `hor` — Hand of Reckoning | 67485 | `wowsims/wotlk ui/retribution_paladin/apls/default.apl.json` i=1 (the APL's TOP row; `sim wowsims/wotlk sim/paladin/hand_of_reckoning.go:16`) |
| `how_wrath` — Hammer of Wrath (WotLK) | 48806 | the same APL i=2 (`sim wowsims/wotlk sim/paladin/hammer_of_wrath.go:12`) |

`how_wrath` is a separate key on purpose: the class's `how` key is the
Era/Forever EXECUTE Hammer of Wrath (24239) and the Wrath channel carries Holy
Wrath, so the WotLK APL's row would otherwise be conflated with both.

**Holy Wrath (`hw`) is KEPT.** The brief's condition ("drop it if it is not an
APL row in any shipped order") is false: it IS an APL row — `p8-stack` i=7
(Holy Wrath 10318 r2, Undead only, `auraKnown(1219193)` + an Undead target).
The row's gate is `{ SOD = true, WRATH = true }` and its source states the
conflict the gap bench found: the WotLK APL has NO Holy Wrath row (its damage
rows are Exorcism 48801 and Consecration 48819 — bench §6.4/§6.5), so the
class keeps its own Undead/Demon line there. **The engine's Wrath order is NOT
changed** (no default-visible change): dropping `hw` from it would remove a
live WotLK prompt, and the bench's own note is that the Wrath order is
"wrong at both ends" — re-cutting it is a separate, operator-visible decision
(§6 below).

**The pre-pull table** (`ST.PALADIN.practice_prepull_rows`) carries the APL's
pre-pull rows, which must NOT appear in the combat rotation: Sanctity Aura
(20218, TBC, @-18.5 s) and 10301 (Forever, @-10 s — the spell's NAME is
UNCONFIRMED: the TBC data maps 10301 to "Retribution Aura"). The pre-pull
DRILL still grades the SEAL (the pre-pull spec above: the seal and its lead);
the two utility rows are citations only — no consumer yet (filed).

## 5. What was NOT changed, and why

* **`nextaction.lua` is UNCHANGED.** The engine's FCFS orders stay the shipped
  prompt order. Re-cutting the Wrath order to the WotLK APL (HoR > HoW >
  Judgement of Light > CS > DS > Exo > Cons) is a LIVE behaviour change on the
  WotLK client, and it cannot be done safely in this scope: the APL's
  judgement row is Judgement of Light (53408), a DIFFERENT spell from the
  class's `judge` key (Judgement 20271), and the guide has no slot for HoR or
  HoW (the paladin declares exactly ten slots — a pinned contract in
  `tests/guide_contract.lua`), so a prompt for either would light no icon and
  read as a hold. The two rows therefore ride the ROTATION TABLE (the APL
  layer) as cited, family-gated rows and are reachable in the WotLK slice; the
  day a display lands, the input lands with it. (HU-13 — the `live`/`engine`
  flag convention across the six classes — is still OPEN; this lane did not
  introduce a new flag convention: the two rows state their status in prose
  (`note`) and their family gate (`families`), the same shape the rogue and
  druid tables use.)
* **`practice_ui.lua` / `practice.lua` are UNCHANGED** (a sibling lane owns
  them). The fix is class-side on purpose: the shared engine's fallback was
  already correct, the class's own builder shadowed it.
* **`ST.PALADIN.practice_rotation_family` stays unpublished.** The panel's
  readout would gain a "Rotation <name>" prefix — a default-visible change the
  brief did not ask for. The slice itself is now published (the panel's button
  vocabulary), which is what F8 asked for.

## 6. Open items for the operator / the next lane

1. **The Wrath order vs the WotLK APL** (bench §6.5): the shipped order
   `cs, judge, ds, cons, exo, hw` misses the APL's top two rows and carries a
   row the APL does not support; the APL's judgement row is a different spell.
   Re-cutting it needs a Judgement-of-Light id + a probe and a guide slot for
   Hand of Reckoning — a separate lane, operator-visible.
2. **The `sotc` label has no row** (bench §6.3): "Seal of the Crusader"
   (20375 on the Era client) is a LABEL and a pre-pull spec, but no shipped
   order names the key, so the Era seal has no rotation line. Not in this
   brief's scope.
3. **In-client confirmation owed** for the ids this lane cites: they are the
   APL's rank ids from the fetched sim files (bench §6.3), i.e. citations, not
   live probes — the class still resolves its own rank-1 ids
   (`nextaction.lua:149-154`).

## 7. Verification

| check | result |
|---|---|
| `tests/paladin_state.lua` | **PASS — 880 checks** (694 before this lane's pins; +186 new) |
| `tests/guide_contract.lua` | **PASS — 1044 checks** (+2 new: the gather's published running order) |
| full harness (`bash tests/run.sh`) | **41 steps, 0 failed** |
| luacheck | **2 warnings / 0 errors in 83 files** (the floor; the three files this lane touched: 0 warnings) |
| line endings | `classes/paladin.lua` stays pure CRLF (5611 CRLF, 0 bare LF); the two test files stay pure LF |
| mutation proofs (`/tmp/opencode` copies) | **10 / 10 killed** |

The mutation set (each applied to a `/tmp/opencode` copy of the tree):

| mutant | killed by |
|---|---|
| the ctx builder refuses the live shape (the fallback is gone) | F1: the live ctx has no swing clock / the decision is nil |
| the live gather fails (the pcall guard swallows it) | F1: the live ctx has no timing |
| the per-entry `source` is dropped | F6: the citation pin |
| the family gate is dropped | F6: the id-gate pin |
| the `tbc_name` is dropped | F6: the TBC-name pin |
| `practice_rotation_for` needs an id again | F8: the argument-free slice pin |
| the gather stops publishing the running order | F8: the SoD running-order pins |
| the two WotLK APL rows are dropped | APL: the row pins + the WotLK slice pins |
| the WotLK Hammer of Wrath id is invented (48807) | APL: the id pin |
| a pre-pull row leaks into the combat rotation | HU-12: the pre-pull pins |

## 8. Files changed (every one of them)

* `classes/paladin.lua` — the ctx builder's live fallback, the gather's
  published running order, the rotation table's APL payload (source / note /
  families / ids / tbc_name), the two WotLK APL rows, the pre-pull table, the
  optional `practice_rotation_for` id, the new action keys (`hor`,
  `how_wrath`) and their aliases, and the inputs builder's flat-name
  fallbacks (the seal timers, the reaction/CS delay, the GCD-before-swing).
* `tests/paladin_state.lua` — §25: the F1 / F6 / F8 / APL / HU-12 pins.
* `tests/guide_contract.lua` — the paladin section: the gather publishes the
  running order next to the FCFS mode it decided.

Nothing else was touched: no `practice_ui.lua`, no `practice.lua`, no
`option_tables.lua`, no `config_presets.lua`, no other class, no `main.lua`,
no `diag.lua`, no `compat.lua`, no `hud.lua`, no `bars.lua`, no `run.sh`, no TOC,
no version, no docs, no lint config, no version control.
