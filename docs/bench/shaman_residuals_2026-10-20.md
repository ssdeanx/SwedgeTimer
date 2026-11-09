# Shaman APL residuals — closure report (2026-10-20)

Desk: `shaman-residuals`. Scope: `classes/shaman.lua`, `shaman_guide.lua`,
`option_tables.lua` (the Frost Shock widget only), `config_presets.lua` (that
widget's default only), `tests/shaman_state.lua`,
`tests/shaman_guide_state.lua`, `tests/options_load_state.lua` (that widget's
pins only). No git, no lint-config change, no TOC/version/doc change, no other
class touched, no other option file touched.

Source of truth: `bench/shaman_apl_utility_build_2026-10-20.md` §5 (the filed
residuals F1 / the Frost Shock option / the Chain Lightning sensor / C5), the
APL files the lane fetched (re-read here from
`/tmp/opencode/shaman_apl/`, plus `phase_4` fetched again for the Chain
Lightning citation), the clients' FrameXML in `/home/sam/wow-ui-source`, and
`bench/filed_closure_sweep_2026-10-19.md` §4.1 (S-11) + §10 (O-1, O-4).

---

## 1. What landed

### 1.1 The Lightning Shield maintain is no longer a per-family gap (F1)

The lane's exact spec (§5 F1) is implemented, and the shipped line no longer
reads a wrong value on any family:

| where | before | after |
|---|---|---|
| the rotation row's `families` | `{ "WRATH" }` | `{ "WRATH", "SOD", "FOREVER" }` |
| the rotation row's ids | `spell_id = 49281` only | `spell_id = 49281` + `spell_ids = { WRATH = 49281, SOD = 10432, FOREVER = 10432 }` |
| the gather's `lightningshield_due` gate | `st.family == "WRATH"` | the engine's new pure helper: WRATH, FOREVER, or the ERA token **with** the MW-rune latch (the SoD build) |
| the engine's rule 11b | `st.family == "WRATH"` | `st.shaman_guide.get_lightningshield_family_gate(st.family, inputs.mw_observed)` |

The APL citations were re-verified against the fetched files (not taken on
trust):

* **SoD** — `wowsims/sod ui/enhancement_shaman/apls/phase_6.apl.json`
  priorityList **i=8**: `not auraIsActive(10432 r7)` → `castSpell 10432 r7`;
  and `phase_4.apl.json` **i=0**: the same row.
* **Forever** — `wowsims/forever ui/specs/shaman/enhancement/apls/default.apl.json`
  **i=6**: `not auraIsActive(10432)` → `castSpell 10432`.
* **Era-base and TBC** — the classic default APL (7 rows) and the tbc-new
  default APL (8 rows) carry **no** Lightning Shield spell at all, so those
  builds must never fire the maintain. The helper is the gate that says so.

**A known gate was added** (the Searing maintain's shape): the Lightning
Shield is a **talent**, so a build without it must never be prompted — the
probe asks the client's own resolved id (the guide slot's id, re-pointed by
NAME at `post_init`), and an unreadable answer keeps the maintain silent
(unknown-hides). Without it, the newly-enabled SoD/Forever families could
prompt a spell the player does not have — a wrong prompt, i.e. exactly the
failure the residual warns about. The gate also covers the Wrath family, where
the shipped id 49281 is still marked UNCONFIRMED.

**Deliberately NOT changed** (out of the residual's scope, filed below): the
HUD's Lightning Shield mirror (`hud_show_lightningshield`) keeps its
family-agnostic cue — it is display-only, ships **false** (hidden), and gating
it would move `tests/hud_state.lua`'s pins (that suite runs the **TBC** family,
where the mirror's glow is pinned).

### 1.2 The Frost Shock choice is a real, class-owned input with a widget

The TBC APL's `Shocks` group picks **one** filler: its group reference sets
`"Filler Shock"` to the valueVariable **Earth Shock** (the group's row 3,
25454 r8); the ALTERNATIVE is the group's row 2, **Frost Shock 25464 r5**.
The live gather never stated the choice, so the engine's rule 13b arm was dark
on every live client.

* **The class owns the read** — `classes/shaman.lua`'s gather reads the
  player's own option (`db.guide_filler_shock`) and states the engine's frozen
  token (`st.shaman_guide.FILLER_SHOCK_FROST` = `"FROST"`) **only** when the
  player picked Frost Shock, and **only** on the TBC token. A missing option
  value, or any other value, states nothing → the APL's Earth Shock default
  stands (nil-safe, no default-visible change).
* **The option's own vocabulary** — `ST.SHAMAN.FILLER_SHOCK_OPTION_EARTH` /
  `..._FROST` (`"earth"` / `"frost"`), table fields (the class file sits at
  Lua 5.1's 200-local ceiling: 198 top-level locals, unchanged).
* **The widget** — `option_tables.lua`'s `guide_filler_shock` (a `select`,
  order 3.102, right after `guide_flameshock_refresh`): `{ earth = "Earth
  Shock", frost = "Frost Shock" }`, the shared class getter/setter.
* **The default** — `config_presets.lua`: `guide_filler_shock = "earth"` (the
  APL's own default), documented in place. A fresh profile therefore behaves
  **exactly** as before; the Frost Shock arm stays dark until the player asks
  for it.

The engine side needed no change: `uses_frost_shock_filler` already compared
the frozen token, and rules 14/17 already stand silent while the Frost Shock
choice is stated (the group picks one filler).

### 1.3 The Chain Lightning row's flags are honest (the sensor does not exist)

The residual asked for this to be settled, not assumed. It was:

* **Re-verified** on 2026-10-20 in the clients themselves:
  `git grep -i "chain lightning\|ChainLightning"` over `origin/classic_era`,
  `origin/classic_anniversary`, `origin/classic_titan`, `origin/forever` and
  `origin/live` returns **0 hits in every branch** — the clients' FrameXML
  carries no Chain Lightning code at all, so no in-client probe can be written
  against a Blizzard contract.
* **Nothing in the tree feeds it** either: the live gather writes
  `target_count = nil` (every family), and the shared practice engine never
  states the frozen input (`practice.lua` has no `target_count` at all). The
  SoD APL's own condition is `numberTargets >= 2` — a **sim-side** read with no
  client counterpart.

⇒ the row is now `live = false, engine = false`: it has no read **and** no arm
that can fire. A row that claims an arm it cannot have is the failure mode
this project keeps hunting, so the flag had to come down. The `needs` field
names the exact missing read and what would close it (a third-party /
combat-log unit-appear count plus a decision to accept a 0.5 s-lagged count).

**Rule 13 stays** in the frozen engine as the filed skeleton: cutting it is
the **operator's** decision (O-4, "accept a non-client count source, or cut
the rule" — `bench/filed_closure_sweep_2026-10-19.md` §10), not this lane's.
The row's `engine = false` is the honest statement that the arm has **no
producer**; the flag meaning is now written down in the table's header
(`live` = the read exists; `engine` = an arm that can play the line with the
inputs the shipped tree produces).

The table's flag semantics were tightened in the same edit: the rotation
table's header now states both axes explicitly, so the next lane does not have
to re-derive them (HU-13 is still open cross-class).

### 1.4 The twist row's ranks are reconciled with the APL (C5)

The shipped `twist` id **8512** is the Windfury Totem **rank-1** id
(`wowsims/forever sim/shaman/spell_data_auto_gen.go`: `WindfuryTotem: Ranked(
8512, 10613, 10614)`) and the module twists rank 1 **on purpose** (its
DOWNRANK NOTE: rank 1 for mana sustain — max rank ooms in 1-2 min of
twisting). The TBC APL's own air-slot rows cast the sim-exact **rank-5** id
**25587** and the alternation's other half the Grace of Air Totem **25359 r3**
(`tbc-new .../default.apl.json` i=3 group `Totems` rows 1-2; the pre-pull
rows at -8 s and -2 s).

Reconciled, not silently swapped:

* the row keeps `spell_id = 8512` (the shipped fallback) and now carries
  `spell_ids = { TBC = 25587 }` — the APL's sim-exact id;
* the row's citation names both ids, the alternation's Grace of Air half
  (25359) and the reason the fallback stays: the rank choice is the
  **operator's O-1 decision** (`filed_closure_sweep_2026-10-19.md` §10), and
  the guide's name-based icon/label resolution covers the real rank;
* the module's own comment (the `WEAVE_WINDFURY_TOTEM_SPELL_ID` block) now
  says the same thing, so the fallback is honest everywhere it is read.

---

## 2. Validation

* `bash tests/run.sh` — **41 steps, 0 failed** (the tree's floor).
* `luacheck .` — **2 warnings / 0 errors** in 83 files (the tree's floor:
  `compat.lua` + `main.lua`, both untouched by this lane). The four lane
  files and the three suites are warning-free.
* `luac5.1 -p` — clean (run.sh's first step).
* `classes/shaman.lua` — **198 top-level locals** (Lua 5.1's ceiling is 200;
  the new constants are `ST.SHAMAN` table fields, not locals).
* Suites owned by this lane:
  * `tests/shaman_state.lua` — **PASS (785 checks)**
  * `tests/shaman_guide_state.lua` — **PASS (1551 checks)**
  * `tests/options_load_state.lua` — **PASS (3449 checks)**
  * `tests/secret_guard_state.lua` — **PASS (373 checks)** (the class file is
    loadable without the guide module; the gather's guards keep it inert)
* **Mutation proofs: 17/17 killed**
  (`python3 /tmp/opencode/mutations_shaman_residuals.py`, disposable copies
  under `/tmp/opencode`, running the four suites above):
  the brief's named mutant — **`chainlightning_claims_arm`** (the row's
  `engine` flipped back to `true`) — fails a pin in both shaman suites, as
  does `chainlightning_claims_live`; the Lightning Shield family drops (row
  families, the per-family id map, the gather's SoD branch, the known gate,
  the engine's helper for SoD and for Forever, and rule 11b's gate itself);
  the filler choice (dropped, always stated, stated off-TBC, the guard
  removed); the twist row's id map; the option's widget and its default.

**Crossfire note (not this lane's red):** while this lane ran, the **druid**
and **rogue** lanes were editing `classes/druid.lua`, `druid_guide.lua` and
`classes/rogue.lua` in the same tree. The druid's suites (druid_state,
druid_guide_state) and, for a while, `luac5.1 -p` were red with the druid and
rogue lanes' own in-flight edits — none of them in this lane's scope and none
caused by it. One red remained at the end of this lane's run and is **not**
this lane's: **`tests/options_load_state.lua` §9 (the ROGUE panel's db-key
scan)** fails two pins because the rogue lane's new citation prose
(`wowsims/wotlk assets/database/db.json` in `classes/rogue.lua`) matches that
section's `db%.([%a_][%w_]*)` pattern, so a key called `json` is demanded from
the rogue's panel and defaults. The rogue's file and that section are outside
this lane's scope (the rogue lane owns the citation; §9 is not this lane's
widget's pin) — it is filed here for the orchestrator's reconcile. This lane's
own four suites are green throughout, and the full harness was green on the
settled tree before the other lanes started.

---

## 3. Filed (not built here)

* **In-client confirmation owed** (the operator's session): the Lightning
  Shield **known gate** must answer on the Wrath, SoD and Forever clients
  (`api.is_spell_known` on the client's own resolved id) — if a client's spell
  data does not answer, the maintain stays silent (unknown-hides), which is
  the safe direction but would hide a working feature. The SoD build's
  Lightning Shield **talent availability** is not decidable offline (the sim's
  enhancement APL casts it; the vanilla tree files it under the Elemental
  tree) — the known gate covers both cases without a guess.
* **The HUD's Lightning Shield mirror** keeps its family-agnostic cue (see
  §1.1): gating it needs `tests/hud_state.lua`'s pins (the TBC family runs
  there), which is another lane's file.
* **O-1 (the twist rank)** and **O-4 (the Chain Lightning sensor)** stay
  operator decisions — this lane recorded the facts for both and changed
  neither behaviour.
* **The cross-class flag convention (HU-13)** is still open: the shaman's
  table now reads `engine` as "an arm that can play the line with the inputs
  the shipped tree produces", while the rogue lane's rows keep
  `live = false, engine = true` for a rule whose input is never fed. The
  orchestrator owns that ruling; the shaman's reading is stated in the
  table's header so it can be copied or overruled deliberately.

---

## 4. Sources

* The five enhancement APLs (the lane's fetch under `/tmp/opencode/shaman_apl/`
  + `phase_4` re-fetched here) and the sims' own spell data.
* `/home/sam/wow-ui-source` — `git grep` over `origin/classic_era`,
  `origin/classic_anniversary`, `origin/classic_titan`, `origin/forever`,
  `origin/live` (the Chain Lightning check, 0 hits each).
* `bench/shaman_apl_utility_build_2026-10-20.md` §5 (the filed residuals).
* `bench/filed_closure_sweep_2026-10-19.md` §4.1 (S-11) and §10 (O-1, O-4).
* `bench/lessons.md` (the TBC-name / Era-id rule).

Offline only: nothing was loaded in a game client. Per `CAIRN.md` this desk
produced a *source-cited* build, not a verified-in-client one. **Validation
owner: the orchestrator.**
