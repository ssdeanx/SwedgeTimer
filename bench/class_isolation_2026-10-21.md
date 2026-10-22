# Class isolation (shared layer) — 2026-10-21

**Operator order (2026-10-21, verbatim):** "no class features so cross each other. each class
must use their own functions."

This is the second half of that order. The first half (`class-activation`, bench
`bench/class_activation_2026-10-21.md`) is landed: every `classes/<class>.lua` registers its
body as a loader and `main.lua` activates only the SELECTED class. This file is the running
record for the SHARED layer: C1-C7, the provider contract, the machine-enforced guard, the
numbers and every UNCONFIRMED item.

**Status: landed, harness-green, offline proof only (in-client check owed).**

**Resume note (important):** this lane was resumed after a network abort. The orchestrator's
resume brief said "no code changed" — that was WRONG. The first attempt's edits were on disk
(verified: `main.lua` active-class record, `practice_ui.lua` provider seam, the six class
providers, the partially-updated suites). The lane verified the disk state and continued from
there instead of redoing the work. The journal stub was the only stale artifact.

---

## 1. The crossings, C1-C7 — what happened to each

| # | crossing (verified before) | disposition |
|---|---|---|
| C1 | `practice_ui.lua` hardcoded the HUNTER route + `"hunter_forced_move"` | **moved into the class**: `classes/hunter.lua` publishes `ST.HUNTER.practice_panel` (drill key, order, labels, session seams, panel facts). The shared UI asks `ui.practice_panel()` only. |
| C2 | same for SHAMAN + `"shaman_weave"` | moved into `classes/shaman.lua` (`practice_panel`, name-art rule comment moved with it). |
| C3 | same for ROGUE | moved into `classes/rogue.lua` (`practice_panel`). |
| C4 | same for DRUID (powershift route + the `"shift"`/`"Powershift"` literals) | moved into `classes/druid.lua` (`practice_panel`). |
| C5 | `rotationtext.lua:222` DEFINED `ST.PALADIN.get_rotation_key` | the function moved into `classes/paladin.lua` (marked block, extracted by `tests/rotationtext_state.lua` so the shipped body is tested). `RT.provider` reads `ST.active_class`; no provider => no rotation text (hide), never an error. |
| C6 | `designmode.lua:752-794` called paladin-only functions directly | the seal-icons + success-text descriptors moved into `classes/paladin.lua`; the shared registry gained ONE generic seam `DM.register_element(desc)` (calls the existing `register`). The shared registry no longer knows any class; an inactive paladin simply has no such elements. |
| C7 | shared routes keyed on `ST.player_class` | `main.lua:ST:activate_class()` now records `self.active_class` (set on a successful loader; nil on no-loader/throw). `practice_ui.lua` (`practice_class_module`, progress scope, drill keys, scenario) and `rotationtext.lua` (`RT.provider`) key on `ST.active_class`. No active class => no class features; the shared layer never guesses. |

Beyond the table, the same sweep also moved the shared `PRACTICE_DRILL_KEYS` map (class-keyed
progression data: mode/scenario/drills) into each class's `practice_panel.progress`
(`classes/warrior.lua` got a provider with only `progress` for that reason), the panel titles,
the drill hints, the idle status strings and the drift messages. `practice_ui.lua` now contains
NO class module reference in executable code (only 3 documentation comments, which the guard
ignores by design).

## 2. The contract shape chosen (R2 option (a): provider table)

Each class module publishes ONE table inside its loader body:

```lua
ST.<CLASS>.practice_panel = {
    drill_key, title, def_type, icon, drift_message, idle_status, hint_active, hint_stopped,
    scenario_key = function() ... end,      -- the class's own live scenario accessor
    order       = function() ... end,       -- the class's own drill order
    label       = function(key) ... end,    -- the class's own label
    spell_id    = function(key) ... end,    -- the class's own spell id
    status      = function(ui, now) ... end,
    fight_elapsed = function(ui, now) ... end,
    progress    = { mode = ..., scenario = ..., drills = { ... } },
    session = {
        running, active, start, begin, end_session, tick, cast, stop, pause, sync, clear,
        sync_sim, clear_sim,                 -- sim-path seams (paladin / druid)
    },
}
```

Why (a) over duck-typing: one uniform contract for four classes with four different session
shapes; the shared layer reads fields generically, and each class's own functions do the work.
Every shared call is nil-safe and pcall-guarded (R5): a missing/empty provider means "no drill
panel" and the caller degrades (paladin sim / drill list / "No practice for this class.").
`practice.lua` needed NO edit: its class-module resolver already takes the module/key from its
caller, and the shared UI now always hands it the ACTIVE class's module.
The shared `ui.practice_*` helpers are table members, not file-scope locals, because
`practice_ui.lua` sits near the Lua 5.1 local ceiling (it dropped from 199 to 163 locals after
this change — see §6).

Deliberate wording generalisation (error paths only): the per-class refusal strings
("Hunter drill is not available (session rejected).", "Shaman drill session end skipped
(shell missing)." ...) are now the generic "Practice drill is not available (session
rejected)." / "Practice drill session end skipped (shell missing).". The class-specific DRIFT
messages are preserved (the provider supplies `drift_message`). Happy-path behaviour is
unchanged.

## 3. The active-class wiring (C7, main.lua)

`ST:activate_class()` (main.lua): `self.active_class = nil` at entry, `self.active_class = class`
only after the loader succeeded, so a missing loader or a throwing loader leaves no active
class. `tests/main_init_state.lua` pins all four outcomes (Auto = playing class, explicit pick,
no-loader nil, throwing loader nil). `tests/wiring_check.lua` §10 pins the record line and the
two shared readers.

## 4. Files changed (working tree)

Sources:
- `main.lua` — `self.active_class` record in `ST:activate_class()` (nothing else).
- `practice_ui.lua` — the provider seam (`ui.practice_panel` + the generic route/def/session
  helpers), the four hardcoded routes and their session shells deleted, every shared call site
  routed through the provider, `PRACTICE_DRILL_KEYS`/HINT_*_*/title strings removed,
  `practice_class_module`/progress/scope keyed on `ST.active_class`.
- `rotationtext.lua` — paladin provider block removed; `RT.provider` keys on `ST.active_class`.
- `designmode.lua` — paladin descriptors removed; generic `DM.register_element` added.
- `classes/paladin.lua` — `get_rotation_key` (marked block), the two design descriptors
  (marked block), `practice_panel` (progress + sim-path seams).
- `classes/hunter.lua`, `classes/shaman.lua`, `classes/rogue.lua`, `classes/druid.lua` —
  `practice_panel` providers (route, panel facts, session seams).
- `classes/warrior.lua` — `practice_panel.progress` only (its progression facts; no drill
  panel route, unchanged behaviour).

Tests:
- `tests/practice_ui_state.lua` — fixture providers for the hand-built class tables
  (`fixture_panel`), the paladin sim-path provider in `build()`, new C7 pin (active class wins
  over playing class), message pins updated to the generic wording, panel-map pins read the
  class files.
- `tests/rotationtext_state.lua` — extracts the paladin provider block from
  `classes/paladin.lua` (shipped source, not a copy), new C7 pin.
- `tests/designmode_state.lua` — registry count 13->11, extracts the paladin design block and
  drives the descriptors, pins `DM.register_element` + "designmode names no class".
- `tests/main_init_state.lua` — 4 active_class pins.
- `tests/wiring_check.lua` — NEW §10 guard (see §5).
- Collateral fixture lines (same generic pattern the activation lane used; no assertion
  weakened): `tests/rogue_state.lua` (fixture `active_class` + the practice_ui source pins
  rewritten to the provider contract), `tests/druid_state.lua` (2 pins rewritten),
  `tests/options_load_state.lua` (badge sandbox sets `active_class`).

Line endings preserved: practice_ui/main/rotationtext/designmode/hunter/rogue/druid/paladin/
warrior CRLF; shaman LF (as before).

## 5. The new machine-enforced guard (`tests/wiring_check.lua` §10)

"10. class isolation (operator order 2026-10-21: no class features cross)":
- Scans the 10 shared modules (`practice_ui`, `rotationtext`, `designmode`, `hud`, `bars`,
  `nextaction_ui`, `practice`, `practice_progress_ui`, `diag`, `main`) **comment-blanked** for
  `ST.<CLASS>` / `st.<CLASS>` in executable code; every hit FAILS. `main.lua`'s
  `ST.<CLASS> = {}` namespace lines are the only exemption (the activation mechanism's own
  tables; 13 such lines found, floor 6 non-vacuity).
- Pins that `practice_ui.lua` and `rotationtext.lua` contain `active_class` and contain NO
  `ST.player_class` (keying on the playing class fails the build).
- Pins that `main.lua` records `self.active_class = class` and that
  `designmode.lua` defines `function DM.register_element(`.

## 6. Numbers (working tree, 2026-10-21)

- `bash tests/run.sh` → **44 steps, 0 failed**.
- luacheck → **Total: 2 warnings / 0 errors in 86 files** (standing floor: compat.lua
  `addon_name`, main.lua `table.pack`).
- Suites: practice_ui_state **2529/0**, rotationtext_state **244/0**, designmode_state
  **664/0**, main_init_state **950/0**, practice_state **1533/0**, toc_check **1082/0**,
  wiring_check **875/0 (3 accepted known defects, 0 stale)**, class_activation_state **70/0**,
  rogue_state **1114/0**, druid_state **1580/0**, options_load_state **3499/0**; all other
  suites green (full list in the harness run).
- Local ceiling (`toc_check`): `practice_ui.lua` **163** locals (was 199 — the route block and
  the hint strings are gone), densest class prototype unchanged (paladin 182, druid 180,
  warrior 178, shaman 176, hunter 166, rogue 71).

## 7. Mutation proofs (`/tmp/opencode/class-isolation-mut`, copy only — the working tree was never mutated)

Every mutation was applied to the copy; the owning suite was run against the mutated copy;
quoted lines are from those runs.

| # | mutation | proof suite | quoted failure |
|---|---|---|---|
| M1 | `ui.practice_panel()` reads `ST.HUNTER` | wiring_check | `FAIL practice_ui.lua:680 practice_ui.lua names the HUNTER class module in executable code (the shared layer must ask ST.active_class)` |
| M2 | delete `self.active_class = class` from main.lua | wiring_check + main_init_state | `FAIL main.lua:0 main.lua: activation records the class whose loader ran as ST.active_class` + `FAIL  Auto records the playing class as the ACTIVE class ... (got nil, want PALADIN)` (2 failures) |
| M3 | `practice_class_module` keys on `ST.player_class` | wiring_check | `FAIL practice_ui.lua:0 practice_ui.lua: keys its class routes on ST.active_class, never ST.player_class` |
| M3b | `ui.practice_panel()` serves `ST[ST.player_class]` | practice_ui_state | `FAIL  C7: the ACTIVATED class's panel ships, not the playing class's  (got |cFFFF8800Twist Practice|r, want |cFFFF8800Pool Practice|r)` |
| M4 | `RT.provider` keys on `ST.player_class` | wiring_check + rotationtext_state | `FAIL rotationtext.lua:0 rotationtext.lua: keys its class routes on ST.active_class, never ST.player_class` + `FAIL  provider: the ACTIVE class wins over the playing class  (got false, want true)` |
| M5 | designmode registers a descriptor returning `ST.PALADIN` | wiring_check | `FAIL designmode.lua:702 designmode.lua names the PALADIN class module in executable code (the shared layer must ask ST.active_class)` |
| M6 | rotationtext re-defines `ST.PALADIN.get_rotation_key` | wiring_check + rotationtext_state | `FAIL rotationtext.lua:233 rotationtext.lua names the PALADIN class module in executable code ...` + `FAIL  rotationtext.lua no longer defines the paladin provider (the class owns it)` |
| M7 | rogue provider `drill_key` renamed | rogue_state | `FAIL  classes/rogue.lua: the provider names the rogue's own drill key` + `lua5.1: tests/rogue_state.lua:2672: attempt to index field '?' (a nil value)` (the live shell drive loses its route) |
| M8 | `ui.practice_start_drill` order/def validation dropped | practice_ui_state | `FAIL  unresolvable drill order starts no session` + `FAIL  unresolvable weave marker starts no session` (+2) — 4 failures |
| M9 | `function DM.register_element` removed | wiring_check + designmode_state | `FAIL designmode.lua:0 designmode.lua: class-owned design elements register through the generic seam` + `FAIL  designmode.lua exposes register_element` |
| M10 | the drill-clear route guard dropped (`if false`) | practice_ui_state | `FAIL  rogue H2: the live GCD is untouched by the drill  (got nil, want 1.5)` + 7 more (all four drills) |

Baseline re-run of the copy after restore: `bash tests/run.sh` → 44 steps, 0 failed.

## 8. Residuals / UNCONFIRMED

- **UNCONFIRMED (in-client):** the whole contract is offline-proven. Owed in-client: a login on
  each class with `Auto` (panel/HUD/guide/weave/twist unchanged), an explicit non-playing pick
  (the activated class's panel and session appear; the playing class's do not), a Start/Stop
  Fight round-trip per drill, and design mode showing the paladin's seal/success elements only
  when the paladin is the active class.
- **UNCONFIRMED (in-client):** the error-path wording generalisation (generic "Practice drill
  ..." refusals) was not observed in a client; happy paths are unchanged.
- **Filed, not changed:** `practice_ui.lua` still contains two class-NAMED report builders
  (`ui.build_hunter_report` practice_ui.lua:6602, `ui.build_warrior_execute_report`
  practice_ui.lua:6722) and their design descriptors. They reference no class table (the guard
  passes) but they are class-specific features living in the shared file; moving them into the
  class providers is the natural follow-up. Also filed: `main.lua` still branches on
  `self.player_class` in non-practice code (hands, bar colours, aura hooks — e.g.
  main.lua:264-271, 474, 603, 908-910, 1069, 1102, 1375, 1639-1655), which the brief scoped out
  of this lane (main.lua is owned only for the active-class record).
- **Filed:** `tests/practice_ui_state.lua`'s hand-built class tables now mirror the provider
  contract through a fixture helper; the REAL providers are exercised by the class suites
  (rogue_state's live shell drive, hunter/shaman/druid suites' activations) and by
  `tests/class_activation_state.lua` (load-time emptiness).
- **Scope note (verified, not a leak):** `ST.player_class` remains in `designmode.lua:131,146`
  (the playing character's profile defaults) and `practice_progress_ui.lua:202-228,1062`
  (progress-page display labels). Those are config/display lookups for the character at the
  keyboard, not class-feature routes; the §10 active-class pin is deliberately scoped to the
  two route owners (`practice_ui.lua`, `rotationtext.lua`).
- **No TOC/run.sh edits needed** (all changes are in already-listed files; the guard lives in
  the existing wiring_check step).
