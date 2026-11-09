# The paladin-side audit close — the family gate, the two WotLK HUD mirrors, the citation — 2026-10-20

Desk: `paladin-audit-close`. **Inputs:** the deep audit's M2 (the paladin's
rotation slice ignores `families`) and the HUD band lane's filed items
(`bench/paladin_hud_utility_band_2026-10-20.md` §2.1 and §4: the two missing
option widgets, the two missing defaults, the paladin templates' twelve-slot
re-cut, and the off-by-13 sim citation).

**Scope (exactly these files):**

* `classes/paladin.lua` — the practice rotation slice's family gate; the two
  band mirrors' spell-book gate (the state accessor); the `how_wrath` row's sim
  citation; the band diagnostics.
* `nextaction.lua` — the two `how_wrath` sim citations.
* `option_tables.lua` — the two paladin widgets (nothing else).
* `config_presets.lua` — the two paladin defaults + the paladin template rows
  (nothing else).
* `tests/paladin_state.lua`, `tests/options_load_state.lua` (the two widgets'
  pins), `tests/hud_state.lua` (paladin sections), `tests/hud_templates_state.lua`
  (paladin section) and the one bench file that carried the wrong citation.

No git, no lint-config change, no TOC/version/README/CHANGELOG/doc change, no
other class touched.

---

## 1. What landed

### 1.1 M2 — the family gate on the practice rotation slice

`ST.PALADIN.practice_rotation_for` (classes/paladin.lua) now applies the same
`families` predicate the rogue, warrior and druid slices use
(`classes/rogue.lua:2858`):

```lua
if entry and (entry.families == nil or entry.families[family] == true) then
```

on **both** paths: the order's own keys and the APL-row path (the cited rows
the shipped orders do not name).

* **The defect it closes.** The twist order is shared by the classic line
  (ERA / TBC / FOREVER). The `how` row (the execute Hammer of Wrath) declares
  `families = { ERA, SOD, FOREVER }` — the TBC APL has no Hammer of Wrath row
  (bench/rotation_gap_vs_apl_2026-10-20.md §6.2) — but the TBC rotation runs
  the twist order, so the TBC practice panel rendered a "Hammer of Wrath"
  button the TBC rotation can **never** ask for: the engine's execute arm is
  Era/Forever only (`nextaction.lua`'s filler branch: `era_mode or
  forever_mode`). Pressing it graded `out_of_order` → **F** for a spell the
  rotation never wanted.
* **The family token.** The SoD game runs on the **ERA** client, so the ORDER
  names the family — the SoD variants are their own orders (`sod`, `sod_stack`,
  `sod_shock`, `sod_wrath` → `SOD`) — and every other order is the twist tree,
  which answers the client's own family (`compat.lua`'s `st.family`: ERA / TBC /
  FOREVER). The order and the gate therefore never disagree: the running order
  on a SoD client is the SoD one (the live gather publishes it), and the twist
  order is the classic line's.
* **The slices after the gate** (each row's own `families` set decides):

| client / order | slice | dropped |
|---|---|---|
| TBC (twist) | cs, judge, twist, soc, sob, cons, exo | **`how`** |
| Era (twist) | judge, twist, soc, how | cs, sob, cons, exo |
| Forever (twist) | judge, twist, soc, cons, exo, how | cs, sob |
| SoD (sod / sod_stack / sod_shock / sod_wrath) | unchanged | — |
| WotLK (wrath) | hor, how_wrath, cs, judge, ds, cons, exo, hw | — |

* **A client that plays no rotation** (Retail, Cata, Mists) names no row, so
  its slice is empty and the panel falls back to the guide slot vocabulary
  (`practice_ui.lua`'s designed fallback). No such client can run the scenario
  anyway: the rotation scenario needs a live swing engine and those clients run
  the inert stand-in.

**The Era consequence, stated plainly.** The corpus's family gate for the two
filler rows is "SoD, TBC, Forever, WotLK" (bench/rotation_gap_vs_apl_2026-10-20.md
§6.3 — the **Era APL carries no filler row**; `basic_ret.apl.json` is Judgement
+ the primary-seal macro + the two twist seals). The gate therefore drops
`cons` / `exo` from the **Era** client's *rotation* part of the strip — while
the class's own Era twist rule still asks for Consecration (the engine lifts
the AoE gate on Era, `nextaction.lua`'s filler branch). The press stays
reachable: the panel's vocabulary is *rotation ∪ guide slots ∪ the keys the
class has asked for* (`practice_ui.lua`'s `scenario_action_order` +
`scenario_note_action`), so the engine's own expected key joins the strip the
moment the step that wants it opens. The gate narrows the *APL-cited* rows; it
does not silence a press the engine makes.

### 1.2 The two WotLK HUD mirrors are switchable in-game

| piece | where | shape |
|---|---|---|
| the widget | `option_tables.lua` — `hud_show_hor` (order 8.53), `hud_show_how_wrath` (order 8.54) | toggle, the class getter/setter, in the paladin's Icons block beside the other `hud_show_*` slots |
| the default | `config_presets.lua` — `ST.PALADIN.defaults`: `hud_show_hor = false`, `hud_show_how_wrath = false` | the druid-Claw shape (`hud_show_claw = false`): a display-only mirror ships **off** |
| the consumer | `classes/paladin.lua`'s provider gate (`get_hud_state`) | `hud_show_<key> == true` (nil = off, false = off) — cited in both files |

**No default-visible change.** Both keys read `false` on a fresh profile, so
the HUD row is exactly what it was before the band lane: the icons are hidden
at the HUD level (`hud.lua`'s `icon_should_show` hides on `== false`), and the
provider is not even called for them until the player turns them on.

### 1.3 The paladin HUD templates match the shipped slot set

`ST.PALADIN.HUD_TEMPLATES` (config_presets.lua) now names **all fourteen**
shipped slots in each of the three templates — the twelve before plus
`hor` / `how_wrath`. The per-template value follows the class's own rule for
family-specific slots ("SoD-native slots extend P-T2, not P-T1",
bench/paladin_styles_2026-10-19.md §0; P-T2 is "all visible",
bench/hud_templates_2026-10-19.md §1) and the druid's Claw shape (a
display-only mirror: `false` in the defaults, `true` in the "full" template,
`claw = true` in D-T2):

| template | `hor` / `how_wrath` |
|---|---|
| P-T1 "Twist Core" | false |
| P-T2 "Full Ret + Trinkets" | **true** |
| P-T3 "Minimal" | false |

`tests/hud_templates_state.lua`'s paladin entry now lists the fourteen slots,
marks the two band keys `ship_false` (the defaults ship false) and pins the
per-template values, so the suite pins the coverage **and** the placement.

### 1.4 The citation (off by 13) is corrected

`ExtraCastCondition` lives at **`:31-32`** of the fetched
`wowsims/wotlk sim/paladin/hammer_of_wrath.go` (`:18` is the `ManaCost`
`BaseCost` line); the file's other citation in the same table (`:12` for the
spell id 48806) matches exactly, so the file is the same one and the line
number was simply wrong. Corrected in:

* `classes/paladin.lua` — the `how_wrath` rotation row's `source` string.
* `nextaction.lua` — the `how_wrath_remaining` input contract (the file
  header) and the `how_wrath` arm.
* `bench/paladin_apl_utility_build_2026-10-20.md` — the engine-arms table,
  with a correction note that names the defect and the file/line (the bench
  keeps the trail readable).

### 1.5 The band's spell-book gate reads the STATE, not the boolean

(Operator instruction, this session.) The band's gate used the binary
`api.is_spell_known`, which folds "the player does not know it" and "this
client cannot answer" into one `false`, so the gate could not tell the two
apart. It now reads `api.is_spell_known_state` (compat.lua:234 — the tri-state
the compat lane landed):

* `"known"` → the player has the talent → the slot shows.
* `"not_known"` → the build has no such talent → the slot hides.
* `"unknown"` → the client could not answer → the slot hides as well
  (unknown-hides: the slot never shows a spell the player cannot cast) and
  the next tick asks again (the probe is not latched).

Both hiding answers are told apart in the code, and the class records the last
answer per band slot in `ST.PALADIN.hud_band_spell_state` — the HUD's frozen
state table has no room for a reason, so the diagnostic lives on the class
(where the operator's in-client check can read it). `api.is_spell_known` itself
is untouched (contract-frozen by the compat lane's ruling).

---

## 2. Validation

* `bash tests/run.sh` → **41 steps, 0 failed** (the whole harness, from the
  repo root).
* `luacheck .` → **2 warnings / 0 errors in 83 files** — the tree's floor (the
  two warnings are the pre-existing ones in `compat.lua` and `main.lua`,
  untouched here). **The files this lane touched: 0 warnings.**
* `tests/paladin_state.lua` → **PASS (1056 checks)** (was 1041).
* `tests/hud_state.lua` → **PASS (731 checks)** (was 714).
* `tests/hud_templates_state.lua` → **PASS (928 checks)** (was 905).
* `tests/options_load_state.lua` → **PASS (3465 checks)**.
* **Mutation proofs: 18 / 18 killed**
  (`python3 /tmp/opencode/paladin_audit_close_mutations.py`, disposable copies
  under `/tmp/opencode/paladin-audit-close-mut/`):

| mutant | killed by |
|---|---|
| the family gate is dropped on the order-key path | the TBC/Era slice pins (4 checks) |
| the family gate is dropped on the APL-row path | the APL-path shape pin |
| the family token is hardcoded to ERA | the WotLK / SoD slice pins |
| the SoD/Wrath orders fall back to the client family | the WotLK slice pin |
| the band's gate falls back to the binary probe | the state pins (6 checks) |
| the band's `"unknown"` branch is dropped | the band-gate shape pin |
| the band gate stops recording the state | the recorded-state pins |
| the `hud_show_hor` widget is not a toggle | the options widget pins |
| the `hud_show_hor` default is flipped to true | the defaults pins (9 checks) |
| the `hud_show_how_wrath` widget is not a toggle | the options widget pins |
| the `hud_show_how_wrath` default is flipped to true | the defaults pins |
| a template drops the two band slots | the templates' coverage pins (5 checks) |
| the "full" template stops carrying the band | the per-template value pins |
| the "minimal" template drops the band slots | the templates' coverage pins (5 checks) |
| the band's family gate is dropped | the TBC band pins (7 checks) |
| the band's option gate is dropped | the option-gate pins |
| the widget moves off its panel order | the order pins |
| the off-by-13 sim citation returns | the citation pins |

* **Line endings:** `classes/paladin.lua` stays pure CRLF (5991 CRLF / 0 bare
  LF); `nextaction.lua` stays pure CRLF (1440 / 0). `option_tables.lua`,
  `config_presets.lua`, the four test files and the bench file stay pure LF
  (0 CRLF). No trailing whitespace on any touched line.
* **Diff proof:** `diff -u` against the HUD band lane's own snapshot
  (`/tmp/opencode/paladin-hud-band-mut/`, taken before this lane) touches only
  the regions listed in §1 — four hunks in `classes/paladin.lua` (the band
  diagnostics, the band's spell-book gate, the `how_wrath` citation, the
  rotation slice's gate), two in `nextaction.lua` (the two citations), one in
  `option_tables.lua` (the two widgets), three in `config_presets.lua` (the
  two defaults, the templates' comment, the three template rows) and the
  paladin-only regions in the four test files.
* **One number that moved, stated.** The HUD band lane's census counted the
  paladin's reflow provider calls at **12** — with the band keys at *nil*, the
  HUD treats them as wanted and calls the provider (which then hides them).
  With the `false` defaults this lane lands, a fresh profile hides the two band
  icons at the HUD level (`hud.lua`'s `icon_should_show` hides on `== false`),
  so the provider is **not called** for them at all: the shipped profile runs
  10 provider calls, not 12. The visible row is the same either way (a
  provider-hidden slot reserves no width). `tests/hud_state.lua`'s census still
  reads 12 because its fixture leaves the mirror keys unset (nil = wanted) —
  the fixture's db state, not the shipped defaults; the shipped defaults are
  pinned separately in §12 (the `false` keys) and in §1.2.
* **Offline only.** Nothing here was loaded in a game client. Per
  `CAIRN.md` ("two proofs, two words") this is a source-cited build with a
  mutation-proofed offline pass, **not** a verified-in-client one.
  **Validation owner: the orchestrator.**

---

## 3. The operator-visible change

**None, by default.** The two new HUD mirrors stay hidden until the player
turns them on in the paladin panel (Paladin → HUD → Icons → "Hand of
Reckoning" / "Hammer of Wrath (WotLK)"). The practice strip on the TBC client
loses the "Hammer of Wrath" button it never wanted — that is the fix, not a
regression.

Two template picks change something, both explicitly: **P-T2 "Full Ret +
Trinkets"** turns the two band mirrors on (the "all visible" promise, the
druid's Claw shape), and **P-T1 / P-T3** name them off (the family-specific
slots stay out of the core/minimal kits, the SoD-native rule). The band is
WotLK-only, so on every other client the two icons stay hidden whatever the
template says.

The only other visible change: on the **WotLK** client, turning a mirror on
adds its icon to the HUD row (Hand of Reckoning with its own cooldown swipe;
the WotLK Hammer of Wrath with its swipe plus the execute-phase grey above
20 % target health). Every other family hides both (the family gate).

---

## 4. Open / in-client UNCONFIRMED (carried, not closed)

* **The spell-book probe on a talent id** is in-client UNCONFIRMED (the APL
  lane's caveat, §2.4): if the WotLK client answers "not known" for a *learned*
  Hand of Reckoning / Hammer of Wrath, the mirror stays hidden. The gate keeps
  the engine's exact semantics (unknown-hides) rather than inventing a second
  one. **The operator's in-client session decides whether another gate is
  needed.**
* The client's real cooldown lengths (the sim models 6 s / 6-8 s; the client may
  differ) — the HUD reads the client's own number, so the display is
  client-truth either way.
* **The Era client's filler rows** (§1.1) leave the *rotation* part of the
  strip; the presses stay reachable through the panel's asked-for vocabulary.
  If the operator wants the Era filler rows *named* in the rotation slice, the
  corpus's family gate for `cons` / `exo` has to change (an APL citation that
  does not exist today) — filed, not guessed.

---

## 5. Sources

* `bench/paladin_hud_utility_band_2026-10-20.md` §2.1 (the citation
  correction + the fetched sim lines), §4 (the filed widgets / defaults /
  templates).
* `bench/paladin_apl_utility_build_2026-10-20.md` §2.1 (the two APL rows), §2.2
  (the engine arms).
* `bench/rotation_gap_vs_apl_2026-10-20.md` §6.2 (the per-family APL priority
  lists), §6.3 (the per-row family gates).
* `bench/lessons.md` (a bench citation's line number is a claim, not a fact).
* `bench/compat_m3_contract_2026-10-20.md` (the spell-knowledge contract: the
  boolean is contract-frozen, the tri-state is additive).
* `classes/rogue.lua:2858` (the family-gate predicate), `classes/druid.lua:3357`,
  `classes/warrior.lua:4732` (the sibling slices).
* `nextaction.lua`'s filler branch (`era_mode or forever_mode` — the execute
  arm's family gate) and `classes/paladin.lua`'s `practice_rotation` /
  `practice_orders` (the order ids and the rows' `families` sets).
* `wowsims/wotlk sim/paladin/hammer_of_wrath.go` — `:12` (the id 48806),
  `:28` (the 6 s cooldown), `:31-32` (`ExtraCastCondition: sim.IsExecutePhase20()`).
