# Class activation — 2026-10-21

**Operator order (2026-10-21, verbatim):** "you only load the fucking class that is playing.
that should be determined in options. rogue should only load for rogue the rest should not load."

This file is the running record. **A1 (mechanism + the rogue class) is landed.** A2 (the
other five class files + the all-six proof suite) is still owed — see "Filed for the next lanes".

---

## A1 — mechanism + the rogue class (landed)

### The contract as implemented

- **Loader shape:** `classes/rogue.lua` keeps its header (`local addon_name, st = ...` /
  `local ST = LibStub(...)`) and wraps the ORIGINAL body (unchanged, not re-indented) in
  `st.class_loaders["ROGUE"] = function() ... end`. Two edits only: the registration after
  the header (classes/rogue.lua:79-80) and the closing `end` as the file's last statement.
  The body closure carries 71 locals + 2 upvalues; with the header's 3 locals the old file
  count was 74. The main chunk is now 3 locals.
- **Activation:** `ST:activate_class()` (main.lua:641) is called from `ST:init_libs()`
  (main.lua:691), immediately before `interfaces_are_initialised = true`, and therefore
  before `ST:post_init()` (main.lua:704) and before the class `post_init` hook
  (main.lua:821-822), which is what brings up the practice panel and the HUD.
- **Selection:** `Auto` (the default) resolves to `self.player_class`; an explicit class
  token activates that class's loader instead. Read from the playing class's profile table
  (`get_class_table()`), i.e. the existing shared-option path
  `config_presets.lua -> config.lua -> ST.defaults`.
- **Fail closed:** a missing loader never aborts init; a loader that throws is pcall'd, the
  class table is reset to a fresh `{}` (no half-state) and the user sees one line. A
  selected class that has no module (explicit pick, empty table) also gets one line. `Auto`
  on a class with no module stays silent (today's unsupported-class path — see
  "Decisions / UNCONFIRMED").
- **Idempotence:** `self.class_activated` makes activation a once-per-session event; a late
  library report cannot re-run a loader.

### Activation order (pinned)

1. Every addon file executes; `classes/rogue.lua` registers
   `st.class_loaders["ROGUE"]` **without running the body** (SavedVariables are not readable
   yet).
2. `OnInitialize`: player class (`UnitClass`), AceDB (`SwedgeTimerDB`), options, lib
   callbacks/events.
3. `init_libs` gates on `lrc_ready and stl_ready`, then **`self:activate_class()`**, then
   `interfaces_are_initialised = true`.
4. `init_timers`, `init_range_finders`.
5. `post_init`: class `post_init` hook (practice panel / HUD init live inside it).

`tests/main_init_state.lua` pins `hook_order == {"activate", "post_init"}`; the hooks do not
exist before activation in that sandbox. `tests/wiring_check.lua` §9b pins the source order
`activate_call < post_init_call` inside `init_libs`.

### The option

- **Key:** `class_activation` (per-class profile table: `db.profile[CLASS].class_activation`).
- **Default:** `"Auto"`, shipped in `ST.class_defaults` (config_presets.lua:107), which
  config.lua folds into `ST.defaults` as the `['**']` wildcard for every class table.
- **Widget:** option_tables.lua:199 — `type = "select"`, order 1.14, name "Class module".
- **Values:** `Auto` (labelled "Auto (your class)"), `DRUID`, `HUNTER`, `PALADIN`, `ROGUE`,
  `SHAMAN`, `WARRIOR`.
- **Help (verbatim):** "Which class module SwedgeTimer activates. Auto (the default)
  activates the class you are playing; picking a class activates that class's module
  instead. Only the selected class is loaded - the others stay inert. Applies at the next
  login or reload."
- **nil-safe:** getter returns `"Auto"` for nil/false; `hidden` returns true only when the
  stored value is exactly `false` (nil shows the widget). Setter writes the class table key.
- No other option's default, label or behaviour changed. With `Auto`, the rogue's hooks,
  practice panel, HUD and guide are the same paths as before (all rogue suites green).

### Suite numbers (working tree, 2026-10-21)

`bash tests/run.sh` → **43 steps, 0 failed**; luacheck **Total: 2 warnings / 0 errors in 85 files**.

| suite | result |
|---|---|
| `tests/smoke.lua` | 232 checks, 0 failures |
| `tests/rogue_state.lua` | 1116 checks, 0 failures |
| `tests/guide_contract.lua` | 1052 checks, 0 failures |
| `tests/practice_ui_state.lua` | 2522 checks, 0 failures |
| `tests/neutral_actions_state.lua` | 7026 checks, 0 failures |
| `tests/prepull_contract_state.lua` | 124 checks, 0 failures |
| `tests/hud_state.lua` | 817 checks, 0 failures |
| `tests/rotationtext_state.lua` | 242 checks, 0 failures |
| `tests/main_init_state.lua` | 946 checks, 0 failures (new §7c: activation order + fail-closed) |
| `tests/options_load_state.lua` | 3499 checks, 0 failed |
| `tests/toc_check.lua` | 1081 checks, 0 failures |
| `tests/wiring_check.lua` | 794 checks, 0 failures, 3 accepted known defects, 0 stale |

### Mutation proofs (`/tmp/opencode/class-activation-a1`, copy without Media/docs/.git)

Every mutation was applied to the copy only; the working tree was never mutated. The
relevant suite was run against the mutated copy; quoted failure lines are from those runs.

| # | mutation | proof suite | quoted failure |
|---|---|---|---|
| M1 | delete `self:activate_class()` from `init_libs` | main_init_state | `FAIL  the class post_init hook ran once  (got nil, want 1)` |
| M2 | disable the no-loader notice (`if false then`) | main_init_state | `FAIL  the missing module prints exactly one notice  (got 0, want 1)` |
| M3 | drop `pcall(loader)` (call it directly) | main_init_state | `lua5.1: tests/main_init_state.lua:2146: loader exploded` (init aborts) |
| M4 | drop the `self[class] = {}` rollback | main_init_state | `FAIL  the half-populated class table was rolled back` |
| M5 | drop the `Auto` resolution | main_init_state | `FAIL  the class post_init hook ran once  (got nil, want 1)` |
| M6a | unwrap `classes/rogue.lua` (remove registry + closing end) | wiring_check | `FAIL classes/rogue.lua:0 classes/rogue.lua: the loader registry is created at file scope` (+ 3 more) |
| M6b | remove the activation call from `tests/rogue_state.lua` | rogue_state | `FAIL  ROGUE.post_init is defined` (+ 4 more) |
| M7 | change the config default to `"MUTATED"` | wiring_check | `FAIL config_presets.lua:27 config_presets.lua: class_activation ships the Auto default in ST.class_defaults` |
| M8 | delete the option widget block | wiring_check | `FAIL option_tables.lua:0 option_tables.lua: the class_activation option exists` (+ 5 more) |
| M9 | move `activate_class()` after `post_init()` | main_init_state | `FAIL  the class post_init hook ran once  (got 0, want 1)` |
| M10 | make the no-loader branch always notice | main_init_state | `FAIL  Auto without a module prints no notice  (got 1, want 0)` |

### Files changed

A1 owned seven; the six shared suites below needed the same activation snippet because they
load `classes/rogue.lua` and assert on its body (combined brief R5: "Any other suite that
loads a class file must be updated too"). The snippet is identical in each: after a
`classes/<name>.lua` chunk loads, if `st.class_loaders[NAME]` is a function, call it — the
same thing main.lua does at init. No assertion in those suites changed.

- `classes/rogue.lua` — loader registration after the header; closing `end` at EOF.
- `main.lua` — `ST:activate_class()` + the call in `init_libs` (main.lua:641-676, 691).
- `option_tables.lua` — the `class_activation` dropdown (line 199).
- `config_presets.lua` — `class_activation = "Auto"` in `ST.class_defaults` (line 107).
- `tests/rogue_state.lua` — activates the ROGUE loader right after the class file loads.
- `tests/main_init_state.lua` — loader-based class fixture + §7c order/fail-closed pins.
- `tests/wiring_check.lua` — §9 contract pins; §7a/§8 allow the sanctioned
  `st.class_loaders` registry write; §8 runs registered loaders; accepted-defect prose line
  citations refreshed after the main.lua shift (521/520 -> 702/692).
- `tests/guide_contract.lua`, `tests/practice_ui_state.lua`,
  `tests/neutral_actions_state.lua`, `tests/prepull_contract_state.lua`,
  `tests/hud_state.lua`, `tests/rotationtext_state.lua` — generic loader activation in
  their class-module sandboxes (harness green; A2's five classes will need no further edit
  there).

### Filed for the next lanes

1. **`tests/toc_check.lua` local-budget guard is now measuring the wrapper, not the body.**
   Current count for `classes/rogue.lua` is reported as **3 file-scope locals** (limit 190,
   headroom 197) while the real body closure is **71 locals** (`luac5.1 -l -l`: `0 params,
   103 slots, 2 upvalues, 71 locals`). The Lua 5.1 ceiling is per function prototype, so the
   guard must measure the tightest prototype, not the first.
   - `tests/toc_check.lua:991-999` — `compiler_local_count` returns the first
     `"upvalues, (%d+) locals"` match. Exact change: scan every match and return the MAX:
     ```lua
     local function compiler_local_count(path)
         local max_n = nil
         for _, line in ipairs(shell_lines('luac5.1 -l -l "' .. path .. '" 2>/dev/null')) do
             local n = line:match("upvalues, (%d+) locals")
             if n then
                 n = tonumber(n)
                 if max_n == nil or n > max_n then max_n = n end
             end
         end
         return max_n
     end
     ```
   - `tests/toc_check.lua:965-971` — the comment says nested functions are excluded from the
     count; that is exactly the old assumption and now hides the wrapped body. Update it to
     say the guard takes the maximum across all prototypes (the per-function ceiling).
   No baseline entry is needed: the max is 71 (headroom 129).
2. **A2: wrap the other five class files** (`druid`, `hunter`, `paladin`, `shaman`,
   `warrior`) with the same two edits; add their suite activations if not already covered
   (the six shared suites above already auto-activate any registered loader); add the new
   all-six proof suite and its `tests/run.sh` line (orchestrator owns run.sh).
3. **A2 / decision needed — `Auto` + a missing module is silent by design in A1.** The
   fail-closed notice fires only for an EXPLICIT selection (or a throwing loader). Rationale:
   a class this addon has no module for (mage/priest/etc.) must not start printing a new
   line at every login — that would be a user-visible change outside the order. After A2,
   if the operator wants an `Auto`-path notice for a SUPPORTED class whose file failed to
   load, the mechanism needs a registry of the six module classes (e.g. pre-seeding
   `st.class_loaders` with the six keys in main.lua and treating "key present, loader
   absent, table empty" as the fail-closed case). Not built in A1.
4. **No TOC edits needed.** All seven TOCs list `classes\rogue.lua` after `main.lua` and
   `config.lua` (lines: base/Vanilla/TBC/Wrath rogue at 77, Cata/Mists/Mainline at 76;
   main at 58/57, config at 70/69). The loader registration works under the existing order.
5. **Prose line citations elsewhere.** The main.lua insertion shifted later lines by +53 in
   the cited ranges. Comments in `tests/options_load_state.lua:16-17,207-216,353,501`
   (`main.lua:281`, `main.lua:303`, `main.lua:81`), `tests/druid_state.lua:988`,
   `tests/secret_guard_state.lua:938`, `tests/swing_source_state.lua:248` and
   `tests/wiring_check.lua:1016-1017` may now be stale. They are comments only (no assertion
   reads them) and those files belong to other lanes; the owning lane should re-point them.

### Decisions / UNCONFIRMED

- **UNCONFIRMED (in-client):** the whole contract is proven offline only. Owed in-client:
  a rogue login (Auto loads rogue, practice panel/HUD/guide appear), the options dropdown
  rendering/order, `/reload` after switching the dropdown, and a non-rogue login with
  `Auto` (no notice, no class features).
- **UNCONFIRMED (in-client):** an explicit non-playing class (e.g. ROGUE selected on a
  warrior) activates the rogue loader by design ("lets the owner exercise a class he is not
  playing"), but its interaction with the warrior's bar/hand layout is untested in-client.
- **UNCONFIRMED:** `st.class_loaders` is a new file-scope namespace write in a class module.
  It is a plain table assignment (`st.class_loaders = st.class_loaders or {}`), sanctioned
  for this mechanism; `tests/wiring_check.lua` §7a/§8 allow exactly that key and §9 pins it.
  In-client load on each flavor is still the real check.
- **Decision recorded:** A1 keeps the six `ST.<CLASS>` tables in main.lua as the mechanism's
  namespace (all 13 class tables still exist); no shared file names a class for a FEATURE.
- **Known guard weakening until the filed fix lands:** `toc_check` sees 3 locals for the
  wrapped rogue file; the real closure is 71, well under 190/200.

---

## A2 — the other five classes + the all-six proof suite (landed)

### The five wraps (same two edits as A1)

Each file keeps its header (`local addon_name, st = ...` / `local ST = ...`), then
`st.class_loaders = st.class_loaders or {}` / `st.class_loaders["<CLASS>"] = function()`,
then the ORIGINAL body unchanged (not re-indented, not reformatted), then one closing
`end` as the file's last statement. Line count +4 per file; endings preserved per file
(druid/hunter/paladin/warrior CRLF, shaman LF — shaman was already LF).

| file | registry lines | pre-wrap main-chunk locals | post-wrap main chunk / body (max) |
|---|---|---|---|
| classes/druid.lua | 36-37 | 183 | 3 / **180** |
| classes/hunter.lua | 6-7 | 169 | 3 / **166** |
| classes/paladin.lua | 6-7 | 185 | 3 / **182** |
| classes/rogue.lua | 79-80 (A1) | 3 (already wrapped) | 3 / **71** |
| classes/shaman.lua | 24-25 | 179 | 3 / **176** |
| classes/warrior.lua | 11-12 | 181 | 3 / **178** |

All six activate their real body under the suite sandbox; `luac5.1 -p` passes for every
file. Paladin (182) is the tightest class, 8 locals of headroom under the 190 guard.

### Suite activations (no assertion changed)

- `tests/druid_state.lua:482-493`, `tests/hunter_state.lua:373-384`,
  `tests/paladin_state.lua:374-390`, `tests/shaman_state.lua:347-355`,
  `tests/warrior_state.lua:485-496`: after the class chunk loads, assert the loader is
  a function and call it (A1's pattern). `tests/hunter_state.lua` has a SECOND sandbox
  (`build_ui`, line 1762) that loads the hunter file; it got the same activation.
- Collateral, outside the listed A2 ownership (harness would otherwise be red): seven
  more suites load class files without activating. They got the same generic snippet
  A1 used in six shared suites (no assertion changed): `tests/smoke.lua` (build_profile's
  `opts.module`), `tests/warrior_guide_state.lua`, `tests/druid_guide_state.lua`,
  `tests/shaman_guide_state.lua`, `tests/hunter_guide_state.lua` (their MODULES loop),
  `tests/bars_state.lua` (MODULES loop), `tests/secret_guard_state.lua` (its generic
  `modules` builder). `tests/bars_state.lua` also sets `ST.class_activated = true` after
  running every loader: that fixture boots main.lua, whose init would otherwise
  re-activate the player class through A1's `activate_class()` and replace the suite's
  hook spies. Fixture-only; no shipped change.

### New suite: `tests/class_activation_state.lua` (70 checks, 0 failures)

Loads `compat.lua`, `utils.lua` and ALL SIX real class modules into one sandbox, then
executes the SHIPPED activation function (extracted from main.lua's
`ST:activate_class()`, self-contained: player_class / get_class_table / st.class_loaders
/ Print) with a fake addon object. Checks:

1. At load every class file only REGISTERS its loader; all six `ST.<CLASS>` tables are
   empty (6 loader checks + 6 emptiness checks).
2. Auto -> the playing class: DRUID gets `post_init` / `on_bar_update` /
   `practice_scenario_step`, the class table is populated IN PLACE, no notice, and the
   other five tables stay empty.
3. Explicit pick (lower-case `"paladin"`) -> PALADIN, not the playing WARRIOR; the
   playing class stays empty; no notice.
4. A loader that throws fails closed: activation itself does not throw, returns false,
   the half-populated table is rolled back (empty), exactly one notice naming the class
   and carrying the error.
5. A class with no loader (`MONK`) is reported, not crashed: false + `"no-loader"`, one
   notice naming it, every class table still empty.
6. Auto on an unsupported class (`MAGE`) stays silent (the A1 decision), all tables
   empty.

Every emptiness assertion lists the offending registrations (first 8 keys + count), so
a non-selected class that registers anything fails loudly. Any-cwd run verified.

### `tests/toc_check.lua` local-ceiling guard fixed (A1's filed gap)

- `compiler_local_count` now scans EVERY `luac5.1 -l -l` prototype and returns the MAX
  (previously the first match = the wrapper). The comment block (965-971 area) now
  states the ceiling is per function/prototype and the class files keep their real
  count in the nested body.
- Output labels now say "locals in its densest prototype" (the old "file-scope locals"
  would misdescribe a wrapped file).
- PIN added before the tightest-file check: it reads the first prototype (main chunk)
  and the max for `classes/rogue.lua`, asserts max > main chunk and that
  `compiler_local_count` returns the max. It passes as
  `the local guard measures the class body, not the loader wrapper (main chunk 3, body
  71 locals)`.
- Measured after the fix: druid 180, hunter 166, paladin 182, rogue 71, shaman 176,
  warrior 178; practice_ui.lua remains the tightest addon file at 199.

### Numbers

Working tree (WITHOUT the run.sh line — the suite is on disk but unregistered):

- `bash tests/run.sh` -> **43 steps, 1 failed**; the only failure is toc_check's
  registration guards (`unregistered: tests/class_activation_state.lua`;
  `41 registered, 42 on disk`). Every other step PASSES.
- luacheck: **2 warnings / 0 errors in 86 files** (the A1 floor plus the new suite file;
  no new warning — the unused helper was removed).
- `tests/toc_check.lua`: 1082 checks, 2 failures in the working tree, both the
  registration guards above.

Copy at `/tmp/opencode/class-activation-a2` (rsync WITHOUT Media/docs/.git) with the
filed run.sh line added:

- `bash tests/run.sh` -> **44 steps, 0 failed**.
- luacheck: **2 warnings / 0 errors in 86 files**.
- Suites: class_activation_state 70/0; druid_state 1578/0; hunter_state 1736/0;
  paladin_state 1234/0; shaman_state 1064/0; warrior_state 2046/0; toc_check 1082/0;
  wiring_check passes; everything else green.

### The run.sh line (FILED, not edited — orchestrator owns run.sh)

Add after the rogue_state line (line 62 of the current file):

```
run "lua5.1 tests/class_activation_state.lua" lua5.1 tests/class_activation_state.lua
```

Without it, toc_check's "every suite on disk is registered" guard fails (by design).

### Mutation proofs (copy only, `/tmp/opencode/a2-mut`)

| # | mutation | proof suite | quoted failure |
|---|---|---|---|
| P1 | unwrap `classes/druid.lua` | druid_state | `lua5.1: tests/druid_state.lua:488: classes/druid.lua registers the DRUID loader` |
| P2 | unwrap `classes/hunter.lua` | hunter_state | `lua5.1: tests/hunter_state.lua:379: classes/hunter.lua registers the HUNTER loader` |
| P3 | unwrap `classes/paladin.lua` | paladin_state | `lua5.1: tests/paladin_state.lua:383: classes/paladin.lua registers the PALADIN loader` |
| P4 | unwrap `classes/shaman.lua` | shaman_state | `lua5.1: tests/shaman_state.lua:351: classes/shaman.lua registers the SHAMAN loader` |
| P5 | unwrap `classes/warrior.lua` | warrior_state | `lua5.1: tests/warrior_state.lua:491: classes/warrior.lua registers the WARRIOR loader` |
| P6 | toc guard back to first-match | toc_check | `FAIL the local guard measures the class body, not the loader wrapper (main chunk 3, body 71 locals)` |
| P7 | hunter self-activates at load | class_activation_state | `FAIL  at load HUNTER has not executed its body - no functions, tables or hooks: ... and 92 more` |
| P8 | drop `pcall(loader)` (unprotected call) | class_activation_state | `FAIL  a throwing loader does not escape activation` (+ half-state/notice failures) |
| P9 | disable the no-loader notice (`if false`) | class_activation_state | `FAIL  a missing explicit module prints exactly one notice  (got 0, want 1)` |
| P10 | Auto resolves to `"ROGUE"` | class_activation_state | `FAIL  the activated class has its post_init hook  (got nil, want function)` |
| P11 | activation runs EVERY loader | class_activation_state | `FAIL  Auto: HUNTER stays inert - no functions, tables or hooks: ... and 92 more` |

All mutations applied to the copy only; the working tree was never mutated. P1-P5 each
also make the new suite fail on its loader registration assert; P6 quotes the pin; P7
and P11 quote the "stays inert"/load-time emptiness guard.

### Decisions / UNCONFIRMED

- **UNCONFIRMED (in-client):** a login on each of the five classes with `Auto` loads
  only that class (practice panel / HUD / guide / weave / twist unchanged); the options
  dropdown still renders and `/reload` applies a switch; an unsupported class stays
  silent; an explicit non-playing class activates that module (A1's decision) with
  unknown hand/layout interaction. Offline proof only.
- **UNCONFIRMED:** the extracted-activation approach in the new suite depends on
  `ST:activate_class()` keeping its own column-0 `end`. If main.lua's function is split
  or renamed, the suite fails loudly at extraction (assert), never silently.
- **Filed, not fixed:** A1's stale prose line citations remain
  (`tests/options_load_state.lua`, `tests/secret_guard_state.lua:938`,
  `tests/swing_source_state.lua:248`, `tests/wiring_check.lua:1016-1017`) — comments
  only, other lanes.
- **Filed for the orchestrator:** the `tests/run.sh` line above; the working-tree
  harness stays at 43/1 until it lands.
- **Note:** luacheck's file count is 86 now (A1's floor line said 85) because the new
  suite is a new Lua file; warnings are still the standing 2.
