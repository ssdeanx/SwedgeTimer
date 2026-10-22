# Brief: class-activation (2026-10-21) — only the selected class's module executes

**Operator order, 2026-10-21 (verbatim):** "you only load the fucking class that is playing.
that should be determined in options. rogue should only load for rogue the rest should not load."
and "no class features so cross each other. each class must use their own functions."

This lane is the FIRST half of that order: the activation. The isolation half (the shared
layer stops naming classes) is the next lane and is briefed separately — do not start it here.

## Why this is a real defect (not a taste call)
Today all six class modules EXECUTE at load (`SwedgeTimer*.toc:72-77` lists them all), so
all six class tables are populated, all six register their hooks and their tables, and the
shared layer sees six live classes. The class modules do NOT reference each other's code
(verified: no cross-class code reference inside `classes/*.lua`) — but the shared layer does
name classes (`practice_ui.lua:351/405/475/548`, `rotationtext.lua:222`,
`designmode.lua:752-794`), and that is the next lane.

## The contract

R1. **Only the selected class's module EXECUTES.** The five others must contribute NOTHING:
    no tables, no functions, no hooks, no options, no events. Their `ST.<CLASS>` tables stay
    empty. This is the operator's core ask ("rogue should only load for rogue the rest
    should not load").

R2. **The selection is an option.** A dropdown in the options UI:
    `Auto` (default — the class you are playing) + the six class names. `Auto` resolves to
    the playing class at activation time. Picking a class explicitly loads THAT class's
    module instead (this is what the operator asked for: "that should be determined in
    options" — it also lets the owner exercise a class he is not playing).
    - nil-safe (`== false` hides, nil = off) and the DEFAULT must not change any
      default-visible behaviour for the operator's own class: with `Auto` a rogue gets
      exactly the rogue features he has today.
    - The option's default and its help text live with the other shared defaults
      (`config_presets.lua` -> `config.lua` -> `ST.defaults`); document the default in the
      option's help.
    - A class that has no module (or a module that fails to register) must fail closed:
      no crash, no half-state, a clear one-line chat notice.

R3. **Activation happens at init, not at load.** The SavedVariables are only available
    AFTER the addon's files execute and BEFORE `ADDON_LOAD` fires — so the selection CANNOT
    be read while the class files load. The class files therefore REGISTER their body; the
    addon activates the selected one during init, before anything that needs the class
    features (the class `post_init` hook, the practice panel, the HUD). The order is part
    of the contract: pin it in `tests/main_init_state.lua`.

R4. **The class file shape.** Each `classes/<class>.lua` keeps its header and registers its
    body as a loader, e.g.:

    ```lua
    local addon_name, st = ...
    local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
    st.class_loaders = st.class_loaders or {}
    st.class_loaders["ROGUE"] = function()
        -- the whole original body, unchanged
    end
    ```

    The body does not need re-indenting (Lua does not care), but DO NOT reformat it, DO NOT
    touch the vendored style, and keep every existing comment and behaviour.
    Mechanical consequences to respect:
    - The Lua 5.1 ceiling is per FUNCTION scope: 200 locals. The body becomes a function
      scope, so its own local count is unchanged (the six files sit at 74-185) — but the
      repo's local-count guard (`tests/toc_check.lua`, which reads the compiler's own
      count) must still measure the REAL limit (the body closure's count), not the
      wrapper's. If the guard needs to walk the nested scope, that is in scope; if it
      cannot, FILE it with the exact change needed.
    - Inner functions that closed over file-scope locals now close over the closure's
      locals — the same values, the same counts (the 60-upvalue ceiling is unchanged,
      because each inner function still captures only what it already used).
    - `...` (the addon name / addon table) is consumed in the header, outside the closure.

R5. **The suites follow the new shape.** The six class suites load the class file; they must
    now ACTIVATE the class (the sandbox calls the loader, or sets the selection and lets
    the init path do it — pick ONE and use it consistently). The six suites are:
    `tests/rogue_state.lua`, `tests/hunter_state.lua`, `tests/shaman_state.lua`,
    `tests/druid_state.lua`, `tests/paladin_state.lua`, `tests/warrior_state.lua`.
    Any other suite that loads a class file must be updated too — find them, do not assume.

R6. **The proof of the operator's ask.** A new suite (suggested name
    `tests/class_activation_state.lua`) that loads ALL SIX class files in one sandbox,
    activates exactly one, and PROVES:
    - the activated class has its hooks and its practice contract (`practice_scenario_step`
      / `practice_drills` / `practice_rotation` as that class defines them);
    - the other five class tables are EMPTY (no functions, no tables, no hooks);
    - the selection follows the option: `Auto` -> the playing class; an explicit class ->
      that class;
    - a module that fails to register fails closed (no crash, no half-state).
    Name the file after what it proves; the orchestrator adds the `tests/run.sh` line (one
    writer per file — do NOT edit `tests/run.sh`; FILE the line you need).

R7. **No behaviour change for the operator's own class.** With `Auto`, a rogue session must
    be functionally identical to today's rogue session (same hooks, same practice panel, same
    HUD, same guide). The only difference is that the other five classes no longer exist.

## Scope / write permission
- YOU OWN: `classes/rogue.lua`, `classes/hunter.lua`, `classes/shaman.lua`,
  `classes/druid.lua`, `classes/paladin.lua`, `classes/warrior.lua`,
  `tests/rogue_state.lua`, `tests/hunter_state.lua`, `tests/shaman_state.lua`,
  `tests/druid_state.lua`, `tests/paladin_state.lua`, `tests/warrior_state.lua`,
  `main.lua`, `option_tables.lua`, `config_presets.lua`, `tests/main_init_state.lua`,
  `tests/wiring_check.lua`, and your new suite.
- YOU MUST NOT edit: `practice_ui.lua`, `rotationtext.lua`, `designmode.lua`, `hud.lua`,
  `bars.lua`, `nextaction_ui.lua`, `practice.lua`, the TOCs, `tests/run.sh`, `Libs/`,
  `compat.lua`, `config.lua`. If one of those must change for this contract, FILE it on the
  bench with the file:line and the reason — do not edit it. (The shared-layer isolation
  lane owns those and runs AFTER this one.)
- No git. No lint-config changes. Preserve line endings. Warnings: trace them, never
  silence with `_`. No new protected/secure calls.

## Proof required
- `bash tests/run.sh` green, luacheck at the standing floor (2 warnings / 0 errors), and the
  exact numbers reported.
- MUTATION PROOFS on a `/tmp/opencode` COPY (never the working tree) for every new guard:
  remove the guard -> the suite must fail. Copy WITHOUT `Media/`, `docs/`, `.git`.
- The new suite must fail loudly if a non-selected class registers anything.

## Mechanics (skills — CALL these tools, in order)
`bench-read` (desk journal + `bench/lessons.md` + the bench, journals before artifacts) ->
`desk-open` `desks/class-activation/` -> `desk-journal` (append what you did, current state,
next step) -> `signal-write` (done/checkpoint/hands-up JSON into
`desks/class-activation/.signals/`).

## Deliverable
Bench file `bench/class_activation_2026-10-21.md` (confirm absent before writing): the
contract per class, the activation order, the option's key/default/help, the suite numbers,
the mutation list, everything you filed for the next lane, and every UNCONFIRMED item.
This is an OFFLINE proof — the operator's in-client confirmation is owed.

## Validation owner
The orchestrator: it re-runs the harness, re-reads the diff, and hands the operator the
in-client checklist.
