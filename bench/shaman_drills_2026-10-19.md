# bench/shaman_drills_2026-10-19.md — shaman rotation scenario, drills, feature-gap closure

Desk: `shaman-drills`. Date: 2026-10-19. Spec:
`bench/class_features_drills_2026-10-19.md` §2.6 (the shaman section: A feature
checklist, B drill inventory, C target drill set, D target rotation scenario).

**Scope of this lane (orchestrator-fixed):** `classes/shaman.lua`,
`shaman_guide.lua`, `tests/shaman_state.lua`, `tests/shaman_guide_state.lua`.
NOTHING else — no `practice.lua` / `practice_ui.lua` / `practice_progress*.lua` /
`option_tables.lua` / `config*.lua` / other classes / `weave.lua` / `main.lua` /
`diag.lua` / `compat.lua` / `hud.lua` / `bars.lua` / `run.sh` / TOCs / versions /
README / CHANGELOG / docs. No git. No lint-config changes.

**Validation owner:** orchestrator.

---

## 1. What shipped

### 1.1 The three contract hooks

| Hook | Where | Shape |
|---|---|---|
| `ST.SHAMAN.practice_rotation` | `classes/shaman.lua` (the practice surface section) | 18 lines, sim priority order, each with `action` / `label` / `spell_id` (Era id) / `spell_name` (TBC name) / `families` / `live` / `source` (the sim citation) |
| `ST.SHAMAN.practice_scenario_step(self, ctx)` | `classes/shaman.lua` | `{ action = "<slot key>", reason = "<text>" }` or nil (undecidable) |
| `ST.SHAMAN.practice_drills` | `classes/shaman.lua` | 4 entries: `shaman_enh_priority`, `shaman_mw_weave`, `shaman_stormstrike_hold`, `shaman_totem_upkeep` — each with `key` / `label` / `kind` / `description` / `grade(self, ctx)` |

The pure half lives in `shaman_guide.lua` (the practice surface at the end of the
file): `build_practice_inputs`, `practice_step`, `practice_expected`,
`practice_reason`, `band_grade`, `get_practice_pick`, `get_practice_resources`,
`get_practice_family`, and the four graders. The frozen guide contract (the fifteen
slots, the frozen input set, the rule order) is **byte-identical** — the practice
surface is a new section, not a change to the guide.

**The verdict is the engine's own.** `practice_step` runs
`st.shaman_guide.evaluate` on the frozen inputs and returns `out.action` — the
audit's expected-sequence comparison (§2.6 D). The scenario therefore teaches the
same priority the live guide shows, and the drills grade against the same engine.

### 1.2 The ctx the engine has to feed

The contract's ctx is `{ now, last_action, resources, cooldowns }`:

| Bucket | What it carries | Engine input it feeds |
|---|---|---|
| `cooldowns.<key>` | the remaining seconds of a cooldown / debuff window / due flag. The key is the **action key** the rotation table and the guide slots use (`stormstrike`, `flameshock`, `firenova`, `fireele`, `feralspirit`, `lavalash`, `shamanisticrage`, `magma`, `moltenblast`, `twist`, `wftotem`, `goa`, `earthshock`, `shock`); the frozen input's own `_remaining` spelling is accepted as well | `*_remaining` (the shared shock cooldown answers to both `shock` and `earthshock`; Grace of Air to both `goatotem` and `goa`) |
| `resources.<name>` | the frozen input names themselves (`mana_fraction`, `mw_stacks`, `mw_available`, `weave_sub5_ready`, `weave_sub5_is_lavaburst`, `target_count`, `fight_elapsed`, `casting`, `flameshock_allowed`, `stormstrike_hold_enabled`, `windfury_icd_remaining`, `fireele_active`, `clearcasting_active`, `sr_mana_threshold`, `twist_mana_threshold`, `flameshock_refresh`, `magma_refresh`, `swing_remaining`, `gcd_remaining`, `speed`, `weave_available`, `weave_sub5_cast_seconds`) | the same names |
| `resources.family` | the family token for the run (`ERA` / `TBC` / `WRATH` / `FOREVER`) | applied to `st.family` for the call and **restored** afterwards |
| `last_action` | the action under test (the drill's press) | the pick the graders compare |

The practice writer covers **every** frozen input (35 names) and invents none —
pinned by a test that compares the two lists.

Drill-only extras the graders read (all optional, all nil-safe):
`resources.weave_cast_seconds` / `effective_cast`, `resources.swing_duration`,
`resources.swing_remaining`, `resources.latency`, `resources.mw_observed` (the SoD
latch), `resources.ss_ready_at`, `resources.gcd`, `resources.totem_due_at`,
`resources.searing_down`.

### 1.3 The four drills (the audit's D-S1..D-S4)

| Drill key | Grades | Band source |
|---|---|---|
| `shaman_enh_priority` | the expected action vs the press (the engine's verdict) | S on a match, F otherwise; the session band (A/B/C/D on the mis-pick count) is the shared engine's `ROTATION_RUN_BANDS` (practice.lua:3370-3377) — the same table the audit's D-S1 writes |
| `shaman_mw_weave` | the weave fit: the stack floor, the marker margin, the clip | the shared weave margin bands (practice.lua:2405-2411) on **weave.lua's own maths** (the marker fraction + the clip amount) |
| `shaman_stormstrike_hold` | pressing Stormstrike the moment it comes off cooldown vs holding it | the audit's D-S3 bands (S on time, A/B/C late by ≤1/2/3 GCD, D later, F for a hold with the opt-in off) |
| `shaman_totem_upkeep` | the air/fire slot upkeep, and never replacing a live Fire Elemental | the audit's D-S4 bands (S inside the window, A/B/C late by ≤1/2/3 s, D past the window, F for the Fire Elemental) |

A grader returns **nil** when the attempt is not judgeable (the engine shows
UNKNOWN and records no attempt). A hold (RIDE / WAIT) is not a press: the scenario
step returns nil, and D-S1 grades it nothing.

### 1.4 Pins

`tests/shaman_guide_state.lua` + 1 (the pure surface, the class contract, the
shared-engine integration) — **1 286 checks**; `tests/shaman_state.lua` §38 (the
class-side view: the name-vs-id parity, the namespace mirror, the untouched live
guide) — **640 checks**. Both suites green.

**Mutation proofs:** 18 mutations on `/tmp/opencode/shaman-drills-mut/tree` copies
(script `mutate.sh`), **18/18 killed, 0 void** — the family restore, the hold leak,
the D-S1 verdict, the Wrath stack floor, the weave clip, the Stormstrike opt-in,
the lateness band, the Fire Elemental overwrite, the Era Searing gate, the SoD
latch, the fire-slot reader, the Searing reader, the stale-field clear, the
rotation line (count / name / live flag), the drill list, the namespace mirror.
The repo tree was never mutated (verified byte-identical against the copy).

**Harness:** the full repo run was **41 steps / 0 failed** with the repo luacheck at
**2 warnings / 0 errors** (the standing floor) during the lane; this lane's four
files are luacheck 0/0. Afterwards the harness fluctuates only with the parallel
hunter/rogue/engine lanes mid-edit (their suites never load a shaman file) — the
shaman suites stayed green throughout.

---

## 2. The feature checklist (§2.6 A) — closed or filed

**Closed in this lane** (the practice surface; no live behaviour changed):

| Audit row | What closed |
|---|---|
| S-19 Lightning Shield (MISSING) | the rotation line ships with the sim citation (`lightning_shield.go`, the three wotlk APLs, id 49281 UNCONFIRMED). The live slot is filed below. |
| S-20 Call of the Elements (MISSING) | the rotation line ships with the sim citation (`totems.go`, 66842 UNCONFIRMED). The live slot is filed below. |
| S-17 Searing Totem (DEGRADED) | the groundwork the audit lists unwired (the fight clock + the fire-slot reader) is now CONSUMED: `shaman_guide.get_searing_upkeep_due` (Era > 20 s, SoD > 30 s) feeds the D-S4 upkeep drill. The live rule is filed below. |
| S-01 / the rule-7 (now rule-8) hold | the hold is opt-in (`stormstrike_hold_enabled`); D-S3 grades the decision the audit describes (press on cooldown = the default every sim plays, hold = the opt-in). |
| S-02 / S-03 / S-04 the weave | D-S2 grades the stack decision on the real weave maths; the family's stack floor (SoD any / Wrath ≥ 3 / else the MW5 instant) is in the drill. |

**Filed with the reason** (each needs an out-of-scope lane, a new external read, or
an operator decision):

| Audit row | Verdict | Why it is filed (and what a build lane needs) |
|---|---|---|
| S-19 Lightning Shield — live slot | MISSING | needs a 16th guide slot: the guide's slot contract is frozen (the fifteen slots are the header's FROZEN SPEC) and a new slot also needs the guide_contract pin, the HUD mirror, the nextaction_ui mapping and an options widget (the same cut the CoE triage records). The LS-UP read itself is free (the player's aura walk already runs) — the SLOT is the blocker. |
| S-20 Call of the Elements — live slot | MISSING | as above, plus: no water-slot clock exists (only the air slot 4 and the fire slot 1 are read), and 66842 needs in-client confirmation. The CoE triage (`desks/shaman-rotation-fix/journal.md`, the M3 entry) already ruled this cut-with-reason; the APL rank is still owed. |
| S-17 Searing Totem — live rule | DEGRADED | the practice surface consumes the groundwork, but a live rule needs a guide slot (16th) and the same contract/HUD/options work as S-19. The TBC and Forever Searing lines additionally have no sim threshold quoted (S-25) / are the filed static-totem maintain (S-27), so they are not graded either. |
| S-18 Fire Elemental snapshot line-up | DEGRADED | the pure predicate exists (`weave.lua` `is_fireele_lineup_ready`) but its two legs need NEW external data: the Wrath of Air aura id (3738, unconfirmed in-client) and a trinket-stack feed. The weapon swap is not portable under combat lockdown, and the cue needs a HUD/options surface. Filed (the rotation table's `fireele` line carries the citation). |
| S-05 Flame Shock refresh on expiry | DEGRADED | the engine still refreshes at ≤ 3 s (`flameshock_refresh`); the sims refresh on expiry. The engine honours an explicit 0 already — the DEFAULT ships from `config_presets.lua` + the options panel (out of this lane's scope; filed by the rotation-fix lane). |
| S-11 Chain Lightning enemy count | DEGRADED | rule 13 + the slot are live; the feed is nil because no client API counts enemies (no compat probe exists — filed by the rotation-fix lane, F8). The rotation table's line carries the citation. |
| S-15 Twist keyed on the imbue buff | DEGRADED | the stamp model cannot see the imbue's expiry (the aura scan captures active-only); the 0.5 s re-drop threshold and the GoA 25359 id also need in-client confirmation. Filed (F2 class). |
| S-23 Stormstrike cooldown per family | DEGRADED | the sim values are ready (Era 20 s / SoD 6 s / TBC 10 s / Wrath 8 s) and need no new data, but **both live consumers draw the fallback only when the ability is READY**, where the length is discarded: `nextaction_ui.lua:466-483` (`set_icon_cooldown` ignores `full_duration` at `remaining == 0`) and `classes/shaman.lua`'s `hud_ability_cooldown` + `get_hud_state` (the `full` value is dropped when the ability is off cooldown). The shipped 10 therefore never reaches the player on any family — a data change with no visible effect until a consumer is fixed, and the SoD 6 s additionally needs the runtime MW-rune latch. |
| S-24 Autocast cooldowns | MISSING | no portable display in scope: the trinket CDs need a new cue (the HUD has no trinket-by-slot cooldown on the shaman's row) and the racials vary; the autocast-vs-prompt semantics are underspecified. Filed (F1 class). |
| S-26 Twist rank (max-rank 25587 vs the downrank note) | DEGRADED | an open decision, not a bug: the sim twists max rank and pauses at low mana, the module's note says downrank. The orchestrator owns the call (F3). |
| S-27 Forever static totem maintain | MISSING | the ids are unconfirmed (WF 10614 vs the twist slot's 8512, earth 25361, Searing 10438, water 25570) and the slot design is owed (three new guide slots vs reusing twist/magma). Filed (F5). **CORRECTED 2026-10-20** (desk `corpus-corrections`): 8512 is a real **Windfury Totem rank-1** id (the client's rank-1 fallback), so the twist slot is not a wrong id; the **TBC APL's own air-slot rows cast 25587 r5 / 25359 r3**, which is a filed question about the twist row's ranks (`bench/shaman_apl_utility_build_2026-10-20.md` §2 C5; `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **S5**) |
| S-29 Wrath Lightning Shield / Water Shield choice | MISSING | the same cut as S-19 (the shield choice needs mana awareness, which the audit itself defers). |

---

## 3. The cross-lane finding the orchestrator has to rule on

**HU-7 (hands-up.md): the shared engine resolves the class module from the addon
NAMESPACE, but the class tables live on the AceAddon table.**

- `practice.lua:3254-3263` — `H.practice_class_module(class_key)` reads
  `st[class_key]`, i.e. the addon's namespace table.
- `main.lua:68` — the class tables are created on the **AceAddon** table
  (`ST.SHAMAN = {}`); `classes/shaman.lua` (like every class module) reaches it
  through `LibStub("AceAddon-3.0"):GetAddon(addon_name)`. The namespace table and
  the AceAddon table are different objects (Ace3's `NewAddon` creates a fresh
  table — `Libs/AceAddon-3.0/AceAddon-3.0.lua:105-123`).
- Consequence: with the shipped tree, `H.practice_scenario_step("SHAMAN", ...)`
  and `H.practice_drills("SHAMAN")` find NOTHING for every class — the scenario
  and the drills are invisible to the engine.

**What this lane did (the class-side half):** `classes/shaman.lua` mirrors itself
onto the namespace — `st.SHAMAN = ST.SHAMAN` — the same table under both names, so
the engine's lookup reaches the hooks and the two views can never disagree. The
test pins it (`tests/shaman_guide_state.lua`: "the class module is reachable from
the addon namespace") and the shared-engine integration is proven end to end
through the shipped `practice.lua`.

**What the orchestrator / the engine lane owns:** the central fix — one mirror for
all six classes in `main.lua` (or an engine that resolves the AceAddon table
instead of the namespace). The per-class mirror is a stopgap; without the central
fix the other five classes stay invisible to the engine.

---

## 4. UNCONFIRMED carried by this lane

| Item | Where | Why |
|---|---|---|
| Lightning Shield 49281 (Wrath) | the rotation line | the audit's S-19 id; no in-client confirmation (the guide has no slot for it yet) |
| Call of the Elements 66842 (Wrath) | the rotation line | the audit's S-20 id; the CoE triage records it as unconfirmed in-client |
| Searing Totem 10438 | the rotation line | the audit's S-17 id; unconfirmed in-client (the module gates on it) |
| Fire Elemental 2894, Magma 8190, Lava Lash 60103, Molten Blast 425339, Windfury Totem 8512 / 10614, Grace of Air 10627 | the rotation lines | the ids the module already gates on; a wrong id stays silent through the known gate (never a wrong prompt) |
| The SoD 6 s Stormstrike cooldown (S-23) | filed, not wired | operator-confirmed in-client, but the fallback is invisible in the live path (see §2) |
| The CoE APL rank | the rotation table places the line last and says so | the audit quotes no APL index (the CoE triage owes the rank) |

---

## 5. What was NOT done (and why)

- **No live guide rule, slot, HUD row, option or TBC change.** The frozen guide
  contract (the fifteen slots, the frozen input set, the rule order) is
  byte-identical; the practice surface is additive.
- **No change to `weave.lua`** — the drill READS weave.lua's maths
  (`get_marker_fraction`, `get_clip_amount`) instead of copying it.
- **No change to `practice.lua` / `practice_ui.lua`** — the engine registers the
  drills; this lane only implements the class hooks.
- **No multi-target work** (S-11) — the enemy-count sensor does not exist and its
  probe belongs to a compat lane.
- **The rotation table's `live` flag** marks the lines the LIVE guide can play.
  The three slotless lines (Searing, Lightning Shield, Call of the Elements) carry
  `live = false`; the scenario step can never return them (the engine has no rule
  for them), and the test pins that a slotless line never claims to be live.
