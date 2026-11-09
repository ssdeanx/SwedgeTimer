# Brief: class-isolation-shared (2026-10-21) — the shared layer must not own class features

**Status: BRIEFED, NOT DISPATCHED.** This is the second half of the operator's 2026-10-21
order ("no class features so cross each other. each class must use their own functions").
It runs AFTER `class-activation` (bench/briefs/brief_class-activation_2026-10-21.md), which
owns the six class files and their suites.

**Operator order, verbatim:** "no class features so cross each other. each class must use
their own functions."

## The crossings, verified (orchestrator, 2026-10-21)
The class modules themselves are CLEAN: no class module references another class's code
(checked in `classes/*.lua`; every hit was its own `ST.<CLASS>` or a comment). The
crossings are all in the SHARED layer, which is where a shared file owns or names a class's
feature:

| # | shared file | the crossing |
|---|---|---|
| C1 | `practice_ui.lua:350-377` | `use_hunter_drill()` / `hunter_shot_order()` / `hunter_shot_def()` — the shared practice UI hardcodes the HUNTER module and its drill key literal `"hunter_forced_move"` |
| C2 | `practice_ui.lua:404-467` | `use_shaman_drill()` / `shaman_cast_order()` / `shaman_cast_def()` — same for the SHAMAN module and the key literal `"shaman_weave"` |
| C3 | `practice_ui.lua:475-520` | the ROGUE module's drill route |
| C4 | `practice_ui.lua:548-590` | the DRUID module's powershift route |
| C5 | `rotationtext.lua:222` | the shared rotation-text module DEFINES `ST.PALADIN.get_rotation_key` — a shared file writing a class's function |
| C6 | `designmode.lua:752-794` | the shared design registry calls paladin-only functions directly (`ST.PALADIN.save_seal_icons_position`, `reset_seal_icons_position`, `save_twist_text_position`, `reset_twist_text_position`) and gates them on `ST.PALADIN` existing |
| C7 | **everywhere** | the shared layer keys its class routes on `ST.player_class` (the class you are PLAYING). After `class-activation` the ACTIVE class can be a different one (the `class_activation` option lets the owner load a class he is not playing) — so every shared route must key on the ACTIVE class, or an explicitly loaded class's features would never appear. |

## The contract

R0. **The active class is a fact the shared layer can read.** `main.lua` records the class
    whose loader ran (`ST.active_class`, set by `ST:activate_class()` — the lane that owns
    `main.lua` adds it; see the scope note below). Every shared module asks
    `ST[ST.active_class]` — never `ST.player_class`, never a literal class name. When no
    class is active (an unsupported class, a failed loader) the shared layer must degrade to
    "no class features" and never guess.

R1. **No shared module names a class in code.** `practice_ui.lua`, `rotationtext.lua`,
    `designmode.lua`, `hud.lua`, `bars.lua`, `nextaction_ui.lua`, `practice.lua`,
    `practice_progress_ui.lua`, `diag.lua`, `rotationtext.lua` and `main.lua` must not
    reference `ST.<CLASS>` / `st.<CLASS>` for a SPECIFIC class in executable code.
    `main.lua`'s six class tables (the namespace) may stay — but the activation lane owns
    that file; if it must change, coordinate with the orchestrator.
    Comments that explain a class's behaviour stay (they are documentation, not coupling).

R2. **The active class's own functions do the work.** The shared layer asks the ACTIVE
    class module (the one `class-activation` activated) through a uniform contract, and
    renders what it gets. Two acceptable shapes — pick one and use it everywhere:
    (a) the class module publishes a provider table (e.g.
        `ST.<CLASS>.practice_panel = { scenario_key_fn = ..., order = ..., label_fn = ...,
        spell_id_fn = ..., def_type = "shot"|"ability" }`) and the shared layer reads it
        generically; or
    (b) the shared layer duck-types the class module's EXISTING own functions (the hunter
        already owns `get_practice_scenario_key`, `PRACTICE_SHOT_ORDER`,
        `practice_shot_label`, `practice_shot_spell_id`; the shaman owns
        `practice_scenario_key`, `PRACTICE_CAST_ORDER`, `practice_cast_label`,
        `practice_cast_spell_id`) through ONE adapter with no class name and no drill-key
        literal.
    (a) is the cleaner contract; (b) is the smaller diff. Either is acceptable — say which
    you chose and why.

R3. **No class-specific literals in the shared layer.** The drill-key comparisons
    (`"hunter_forced_move"`, `"shaman_weave"`, the rogue's and druid's equivalents) are the
    class's own facts: the class module answers "what is my scenario", and the shared layer
    uses that answer instead of comparing it to a literal it hardcoded.

R4. **`rotationtext.lua` and `designmode.lua` lose their paladin knowledge.** The paladin's
    rotation key moves into `classes/paladin.lua` (the class owns its own function); the
    shared rotation-text module asks the active class generically and treats "the active
    class has no rotation key" as "no rotation text" (never an error, never a guess).
    The paladin's seal/twist design elements move into `classes/paladin.lua` as the class's
    OWN design elements, registered through the generic descriptor mechanism the design
    module already has (`DM.register_template` / the element registry) — the shared design
    registry must not know the paladin.

R5. **A non-active class simply does not exist.** With `class-activation` in place, the five
    inactive classes' tables are EMPTY, so every shared call must be nil-safe against an
    empty table AND against a class with no such function. The shared layer must never
    index a missing function without a guard.

## Scope / write permission
- YOU OWN: `practice_ui.lua`, `rotationtext.lua`, `designmode.lua`, `practice.lua` (its class
  resolution only), `main.lua` (ONLY to record `ST.active_class` in `ST:activate_class()` and
  to expose it — nothing else there), their suites (`tests/practice_ui_state.lua`,
  `tests/rotationtext_state.lua`, `tests/designmode_state.lua`, `tests/practice_state.lua`,
  `tests/main_init_state.lua`), and the class files you must add a provider to or move a
  function into — BUT ONLY AFTER the `class-activation` lane has landed (it owns the class
  files until then; if it has not landed, FILE the change with file:line and wait).
- YOU MUST NOT edit: `option_tables.lua`, `config_presets.lua`, the TOCs, `tests/run.sh`,
  `Libs/`, `compat.lua`, `hud.lua`, `bars.lua`, `nextaction_ui.lua`, `config.lua`
  (unless the contract requires it — then FILE it).
- No git. No lint-config changes. Preserve line endings. Warnings traced, never silenced
  with `_`. No new protected/secure calls. No user-visible change beyond the operator's
  order.

## Proof required
- The existing suites stay green, with the class-specific pins updated to the new contract
  (a pin that asserted "the shared file names the HUNTER module" must become "the shared
  file asks the active class").
- A NEW static guard (in `tests/wiring_check.lua`, which the orchestrator owns — FILE the
  guard, or the orchestrator adds it) that fails when a shared module references a class
  table in executable code. This is the operator's ask, so it must be MACHINE-ENFORCED, not
  a convention.
- `bash tests/run.sh` green + the exact numbers + luacheck at the standing floor.
- MUTATION PROOFS on a `/tmp/opencode` COPY for every new guard.

## Mechanics (skills — CALL these tools, in order)
`bench-read` -> `desk-open desks/class-isolation-shared/` -> `desk-journal` -> `signal-write`.

## Deliverable
`bench/class_isolation_2026-10-21.md`: the crossing table (C1-C6) with what happened to
each, the contract shape chosen, the suite numbers, the mutation list, the filed guard, and
every UNCONFIRMED item.

## Validation owner
The orchestrator.
