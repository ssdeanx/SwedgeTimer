# The hunter's APL utility lines go LIVE — 2026-10-20

Desk: `hunter-utility-live`. **The APL files are the authority**: every id,
index and condition below was re-fetched from `wowsims/{classic,sod,tbc-new,
forever,wotlk}/master` on 2026-10-20 (the raw APL JSON, every
`groupReference` expanded inline), not taken from the gap analysis. The gap
analysis's hunter section (`bench/rotation_gap_vs_apl_2026-10-20.md` §2) is
the INPUT; where it disagrees with the APL, the APL wins.

**Scope:** `classes/hunter.lua` (the reads, the rotation table's flags, the
guide slots, the practice layer), `hunter_guide.lua` (the frozen engine's
arms), `practice_ui.lua` (the practice strip's geometry comment only),
`tests/hunter_state.lua`, `tests/hunter_guide_state.lua`,
`tests/practice_ui_state.lua` (the strip geometry pins only). No git, no
lint-config change, no TOC/version/option change. `hunter_ui.lua` was in
scope and needed no change (it never reads the rotation table or the guide
slots).

---

## 1. What landed

The APL utility rows are now **live**: every row's READ exists and the frozen
engine has an arm that can ask for it.

| family | the rows that went live | the read they use |
|---|---|---|
| ERA | `rapid_fire` (i=1), `serpent` (i=4) | the cooldown probe (`api.GetSpellCooldown`), the Serpent target scan (`api.scan_unit_aura`) |
| SOD | `rapid_fire` (i=7), `kill_shot` (i=12), `raptor_strike` (i=16), `wyvern_strike` (i=17), `aspect_viper` (i=22), `arcane` (i=23), `aspect_falcon` (i=24), `wing_clip` (i=27) | the cooldown probe, the player-buff scan (`api.scan_player_aura`), the target scan |
| TBC | `aspect_viper` (i=0 group), `aspect_hawk` (i=0 group) | the player-buff scan (the TBC client resolves the spell by **NAME** - the name is the primary key there) plus the mana fraction |
| WRATH | `aspect_viper` (i=1), `aspect_dragonhawk` (i=2), `silencing_shot` (i=3), `serpent` (i=5/i=7), `explosive_trap` (i=6), `multi` (i=9/i=10), `black_arrow` (i=8, SV) | the cooldown probe, the player-buff scan, the Serpent target scan |
| FOREVER | `raptor_strike` (i=1), `hunters_mark` (i=2), `mongoose_bite` (i=3), `immolation_trap` (i=5), `wing_clip` (i=6), `serpent` (i=8), `arcane` (i=12), `multi` (i=13) | the cooldown probe, the target scan (the Hunter's Mark), the Serpent target scan |

No new client API: every read is one of the three wrappers the lane confirmed
(`api.GetSpellCooldown`, `api.scan_player_aura`, `api.scan_unit_aura`).

### The two flags (HU-13, the orchestrator ruling)

* `live` — the line's READ exists **and** the line can be evaluated from it.
* `engine` — the frozen engine has an arm that can ask for it.

Every row of every family now carries `live = true` and `engine ~= false`,
except ONE row: the **Forever Aimed Shot**. Its read needs the gather's aimed
block ungated for the Forever family (it runs on the Era set only), and that
is not touched by this lane, so the row keeps naming that read in `needs` and
stays filed. The flag map and the filed row are pinned in
`tests/hunter_state.lua` §26.

### The Forever Steady Shot row is GONE

The task's note ("the Forever client has no Steady Shot at all, so the
Forever spine must not carry one") is applied literally: the
`PRACTICE_ROTATIONS.FOREVER` table no longer carries a Steady Shot row. The
guide's own Forever slot set still declares one (the slot's own business, with
its rank-1 fallback), and the engine's steady arm is gated by
`steady_known` — which is false on a Forever client, because no Steady Shot
rank resolves there. The row's removal is pinned.

## 2. The engine's arms (hunter_guide.lua)

Two arm shapes, both reading the live inputs only:

* a **cooldown line**: known on this client and off cooldown;
* an **aura line** (a buff or a debuff the line maintains): known on this
  client and the buff is **KNOWN DOWN**. The aura feeds are three-state
  (true = up, false = known down, nil = unknown) and **only the false reads
  as due**: a line whose buff is up is NEVER asked for, and an unreadable buff
  is never a "cast it now" (unknown hides).

Two more gates, straight from the APLs:

* the **melee rows** (Raptor Strike, Wyvern Strike, Wing Clip, Mongoose Bite,
  Immolation Trap) also read the weave band: the APL casts them at melee
  range (`unitDistance(Self) <= 5.00` on the Forever, the melee weave on the
  SoD), so a ranged player is never asked to swing in melee. An unknown band
  never prompts.
* the **aspect swaps** also read the mana fraction, on the APL's own
  thresholds (the TBC/SoD Viper at 5%, the WotLK Viper at 10%, the TBC Hawk
  at 25% (`Viper stop`), the WotLK Dragonhawk at 30%). An unknown mana never
  prompts a swap.

### Where each arm sits

The APL's priority order, per family, with two deliberate deviations:

* **the WotLK execute sits ABOVE the Silencing Shot** (the APL has the
  Silencing Shot at i=3 and the Kill Shot at i=4). The shipped rotation
  research calls the execute "always highest when available"
  (`docs/research/rotations_wrath.md:9-16`) and it is a burst moment: a ready
  interrupt must never shadow it.
* the **Era Serpent** asks when the sting is KNOWN DOWN, not at the APL's
  `dotRemainingTime < 5 s` mark. The task's rule ("a line whose buff is up
  must never be asked for") wins over the APL's early-refresh refinement;
  the three-state read does not carry the dot's remaining time.

The Rapid Fire arm moved from its old place (above the Era-SoD Chimera) to
below it, so the Era client asks for it at the ERA APL's i=1 (above the
weave) and the SoD client at the SOD APL's i=7 (behind the Chimera rune at
i=3). The TBC order (Kill Command, Bestial Wrath, Rapid Fire) is unchanged.

## 3. The reads (classes/hunter.lua)

* The **rank tables** grew the ranks the APLs cite: the Kill Shot table adds
  the SoD rune 409593, the Raptor Strike table the SoD/Forever rank 14266,
  the Arcane Shot table the SoD/Forever rank 14287 and the Multi-Shot table
  the WotLK rank 49048. Each table is the resolver's cache key, so an id
  missing from it is simply never detected.
* The **utility lines** resolve their rank with the same knowledge gate the
  Wrath prompts use (`api.is_spell_known`): a client that does not know the
  spell never prompts it, and a client with no knowledge probe stays dark.
  The Multi-Shot's utility pair is separate from the weave's own `multi_known`
  (the Era and TBC cast).
* The **aura reads** are two new three-state readers
  (`utility_buff_active` for the player buffs, `utility_debuff_active` for the
  target debuffs), shaped exactly like the shipped `read_serpent_active`:
  the name leg is the primary key (the TBC client resolves by name), the id
  leg covers the clients that answer with numeric ids, and the secret-aura
  regime turns a missing row into "unknown" instead of "down".
* The **mana fraction** is read only on the families that have an aspect row
  (SoD, TBC, WotLK), so no other client spends the probe.
* The **practice layer** carries the new state into the engine: the aura
  states ride in the ctx under the engine's own input names
  (`ctx.serpent_active`, `ctx.aspect_viper_active`, ...), the weave band
  rides as `ctx.weave_band`, and the mana rides as `ctx.mana_frac` (with
  `ctx.resources.mana` as the sibling alias). An aura state the ctx does not
  carry stays unknown — the scenario never asks for a line whose buff it could
  not read.

## 4. The guide's slots

The engine can now emit the new actions, so the guide's slot sets carry them
(the frame has no cap; the shaman ships eighteen slots and the paladin ten):

| family | slots |
|---|---|
| ERA | aimed, raptor, multi, **rapid_fire, serpent** (5) |
| SOD | chimera, aimed, raptor, multi, **rapid_fire, kill_shot, raptor_strike, wyvern_strike, aspect_viper, arcane, aspect_falcon, wing_clip** (12) |
| TBC | steady, raptor, kill_command, multi, bestial_wrath, rapid_fire, **aspect_viper, aspect_hawk** (8) |
| WRATH | kill_shot, chimera, explosive, aimed, arcane, steady, **aspect_viper, aspect_dragonhawk, silencing_shot, serpent, explosive_trap, multi, black_arrow** (13) |
| FOREVER | hawk, sniper, steady, raptor, **raptor_strike, hunters_mark, mongoose_bite, immolation_trap, wing_clip, serpent, arcane, multi** (12) |

The hunter's own "six of the six allowed" slot contract is therefore GONE: the
slot set now covers the family's whole APL spine. That is the visible change
the task sanctions ("no default-visible change beyond the utility lines the
APL asks for").

## 5. The practice strip's geometry

The filed worry ("the strip is a fixed 74 px with four buttons per row, so
the thirteen-row Wrath spine would spill") does NOT hold in the shipped code:
`practice_row_set_height` already grows the strip with the button lines
(`30 + lines * (button height + gap)`) and the panel's height follows the
strip's. With the thirteen-row Wrath spine the strip carries FOUR button
lines (118 px) and every row gets a button. The lane therefore made the
geometry EXPLICIT and pinned it:

* `practice_ui.lua`: the constants' comment now says the 74 px is the
  TWO-line minimum and that the strip grows with the button lines (no cap, so
  no rotation row is ever cut off by the panel).
* `tests/practice_ui_state.lua` §25: a thirteen-row spine gets thirteen
  buttons, the strip grows past the shipped 74 px, it carries four button
  lines, and the panel grows with it.

(The strip's 74 px is also why the practice panel is not at the local limit:
`practice_ui.lua` has 199 file-scope locals — Lua 5.1's limit is 200 — so
this lane added NO file-scope local there.)

## 6. The scenario's verdict moved (and why that is correct)

The scenario's default state is "every engine-facing row is known and off
cooldown" (the shipped fixture semantics: a fresh scenario has every cooldown
ready). With the whole spine engine-facing, the family's TOP APL row now
leads:

* the WotLK scenario asks for the **Silencing Shot** (the MM APL's i=3) and
  for the **execute** at the E20 (the execute sits above it);
* the Era scenario asks for the **Rapid Fire** (the ERA APL's i=1) and for the
  **Multi** when the Rapid Fire is cooling down.

The live scenario is unaffected: the live ctx carries the client's real
cooldowns (the gather writes every new line's cooldown), so the live run asks
for the line that is really due.

## 7. Validation

* `tests/hunter_state.lua` — PASS (1191 checks; §26 re-cut to the HU-13 flag
  convention, §27 added: the utility layer's live reads, the buff-UP reads and
  the per-family gates).
* `tests/hunter_guide_state.lua` — PASS (1860 checks; §0b added: every
  utility arm, its buff-up suppression, its unknown-hides rule, its melee
  band, its mana gate and its family gate).
* `tests/practice_ui_state.lua` — PASS (1401 checks; §25 added: the strip
  geometry).
* luacheck on the six touched files — 0 warnings / 0 errors.
* The tree harness: 41 steps, **2 failed** — both from the parallel WARRIOR
  lane's crossfire (`tests/warrior_state.lua`,
  `tests/warrior_guide_state.lua`: that lane is landing the same utility work
  for the warrior and its own pins are mid-flight). Every other step is green.
* **11/11 mutation proofs killed** on `/tmp/opencode` copies
  (`python3 /tmp/opencode/mutations_hunter_utility.py` reproduces them): the
  buff-up mutant on the Serpent arm, the Aspect of the Viper arm and the
  Hunter's Mark arm (the task's named "a buff-up line still prompts" proof),
  the Era Serpent arm dropped, the WotLK Explosive Trap arm dropped, the
  player's aspect aura read dropped, the target's Hunter's Mark read dropped,
  a rotation row's live flag flipped back, the engine slice dropping a row,
  the practice strip stopping its growth, and the scenario dropping the aura
  states.

## 8. Still filed (honest)

* the **Forever Aimed Shot** row: its read needs the gather's aimed block
  ungated for the Forever family (the gate runs on the Era set only).
* the **Explosive Trap's DOT**: the APL's own condition is
  `not dotIsActive(49067)` — the trap's DOT on the target. That dot carries
  its own client id, which is not sourced, so the arm gates on the spell's
  readiness (the spell's cooldown) instead. The divergence is recorded in the
  row's `source`.
* the **SoD Kill Shot's "Rapid Fire up" half**: the APL's condition is
  `(Rapid Fire up or E20) and Arcane Shot castable`. The arm models the E20
  half (the execute); the Rapid Fire aura has no read.
* the **Era Rapid Fire's narrow window**: the ERA APL casts it when
  `autoTimeToNext(Ranged) < 0.1 s and spellTimeToReady(20904) < 0.5 s`. The
  arm uses the house pattern for a burst pop (known and off cooldown), like the
  TBC's rule 5. The widening is recorded in the row's `source`.
* the **WotLK / Forever Multi-Shot as a cast shot**: the arm treats it as an
  instant (the WotLK arms never take a clip check). The Forever's Multi is a
  0.5 s cast in the client data; the arm asks for it without a clip check.

## 9. Residual: the per-frame aura cost

The utility layer adds reads to the gather, which runs on the per-frame hunter
visual driver (`ST.HUNTER.on_bar_update`):

* one `api.UnitPower`/`UnitPowerMax` pair per frame on the families that have
  an aspect row (the mana fraction the swaps read);
* one 40-row `api.scan_player_aura` per aspect line that applies to the family
  (the WotLK reads the Viper and the Dragonhawk, the TBC the Viper and the
  Hawk, the SoD the Viper and the Falcon) and one 40-row
  `api.scan_unit_aura` for the target's Hunter's Mark on the Forever.

The shipped gather already walked the target's HARMFUL auras once per frame
for the Serpent Sting, so the aura cost roughly doubles on the families with
aspect rows. The reads are deliberately NOT throttled and NOT mana-gated: the
task's rule is strict ("a line whose buff is up must never be asked for"), and
a cached or conditional read could violate it inside the cache window. If the
operator wants the cost down, the filed follow-up is a throttled aspect probe
(the ISS/LnL badge discipline: 0.5 s rescan) with the arm's buff-up rule
re-proved against the cache.

