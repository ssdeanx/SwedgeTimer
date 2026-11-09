# Brief: class-activation-A1 (2026-10-21) — the mechanism + the rogue class

**This is a SPLIT of `bench/briefs/brief_class-activation_2026-10-21.md`.** The first
dispatch of that brief DIED SILENTLY (no text, no files, no desk) — most likely a context
blowup from six 200 KB class files plus six 200 KB suites in one agent. So the work is
split. **A1 (this brief) = the mechanism + the rogue class.** A2 (next) = the other five
classes + the full proof suite.

**CONTEXT DISCIPLINE (the likely cause of the death):** do NOT read whole files. `classes/*.lua`
are 160-310 KB each and the suites are 180-300 KB each. Use targeted `grep`/`sed -n` reads
of the regions you need (the header of a class file, the function you are changing), and
make edits with small, surgical patches. Never cat a class file or a suite end to end.

## The operator's order (2026-10-21, verbatim)
"you only load the fucking class that is playing. that should be determined in options. rogue
should only load for rogue the rest should not load."

A1 delivers the MECHANISM and proves it on the rogue. A2 wraps the other five classes and
adds the full proof suite. After A1 the rogue session already works exactly as the operator
asked; after A2 the other five classes are inert too.

## A1 scope

### 1. The class-file shape (classes/rogue.lua only)
Keep the header as it is, then register the body as a loader:

```lua
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
st.class_loaders = st.class_loaders or {}
st.class_loaders["ROGUE"] = function()
    -- the ORIGINAL body, unchanged, not re-indented, not reformatted
end
```

The body is everything after the header. Two edits: the loader registration, and a closing
`end` at the end of the file. Nothing else in the file changes — no comments, no
reformatting, no reordering.
- The Lua 5.1 ceiling is per function scope: the body becomes one function scope, so its
  local count is unchanged (`classes/rogue.lua` is at 74 locals, the limit is 200).
- Inner functions now close over the closure's locals — same values, same counts.
- `...` is consumed in the header, OUTSIDE the closure.
- The file's own `local` count (the repo's `tests/toc_check.lua` guard) will now measure the
  WRAPPER, not the body. That guard is NOT yours — FILE the exact change needed (it must
  measure the nested scope) with the file:line.

### 2. The activation (main.lua)
- The SavedVariables are readable only AFTER the files execute and BEFORE `ADDON_LOAD`, so
  the selection cannot be read at file scope: the loader is registered at load, the SELECTED
  class is activated during init, BEFORE anything that needs the class features (the class
  `post_init` hook, the practice panel, the HUD). The ORDER is part of the contract.
- The selection value: `Auto` (resolve to the playing class) or one of the six class names.
  Read it from the shared defaults the way the other shared options do (`config_presets.lua`
  -> `config.lua` -> `ST.defaults`); use the existing shared-option mechanism, do not invent
  a second one.
- Activation = call the selected class's loader. The other five loaders are NOT called, so
  their class tables stay EMPTY.
- Fail closed: a class with no loader (or a loader that throws) must not crash init, must
  not leave half-state, and must say one clear line in chat.
- `main.lua` keeps the six class tables as the namespace (that is the mechanism's registry,
  not a class feature) — but no shared file may name a class for a FEATURE (that is A2's
  job).

### 3. The option (option_tables.lua + config_presets.lua)
- A dropdown in the options UI: `Auto` (default — the class you are playing) + the six class
  names. The default must be documented in the option's help text.
- nil-safe (`== false` hides, nil = off). With `Auto`, a rogue session must be functionally
  IDENTICAL to today's rogue session: same hooks, same practice panel, same HUD, same guide.
- No other option's default, label or behaviour changes.

### 4. The suites
- `tests/rogue_state.lua` loads `classes/rogue.lua`; it must now ACTIVATE the rogue (call
  the loader, or set the selection and let the init path do it — pick ONE, use it
  consistently). Every other assertion in that suite stays as it is.
- `tests/main_init_state.lua`: pin the activation order (activation before the class
  `post_init` hook and before the practice/HUD init), and pin the fail-closed path.
- `tests/wiring_check.lua`: pin the contract — the loader registration in
  `classes/rogue.lua`, the activation call in `main.lua`, the option in
  `option_tables.lua` + its default in `config_presets.lua`.

### 5. Proof
- `bash tests/run.sh` green with the exact numbers; luacheck at the standing floor
  (2 warnings / 0 errors in 85 files).
- MUTATION PROOFS on a `/tmp/opencode` COPY (never the working tree) for every new guard:
  remove the guard -> the suite must fail. Copy WITHOUT `Media/`, `docs/`, `.git`.
- A new suite is A2's job (it proves all six). A1 proves the rogue end to end in the
  existing suites.

## Scope / write permission
- YOU OWN: `classes/rogue.lua`, `tests/rogue_state.lua`, `main.lua`, `option_tables.lua`,
  `config_presets.lua`, `tests/main_init_state.lua`, `tests/wiring_check.lua`.
- YOU MUST NOT edit: the other five class files and their suites (A2 owns them),
  `practice_ui.lua`, `rotationtext.lua`, `designmode.lua`, `hud.lua`, `bars.lua`,
  `nextaction_ui.lua`, `practice.lua`, the TOCs, `tests/run.sh`, `Libs/`, `compat.lua`,
  `config.lua`. If one of those must change, FILE it with file:line and the reason.
- No git. No lint-config changes. Preserve file endings. Warnings traced, never silenced
  with `_`. No new protected/secure calls. No user-visible change beyond the operator's
  order.

## Mechanics (skills — CALL these tools, in order)
`bench-read` (desk journal + `bench/lessons.md` + the bench, journals before artifacts) ->
`desk-open desks/class-activation/` -> `desk-journal` (append what you did, current state,
next step) -> `signal-write` (done/checkpoint JSON into `desks/class-activation/.signals/`).

## Deliverable
Append a dated section to `bench/class_activation_2026-10-21.md` (create it if absent —
confirm first — with a short A1 section; NEVER overwrite what is there): the contract, the
activation order, the option's key/default/help, the suite numbers, the mutation list, what
you filed for A2, and every UNCONFIRMED item. Plus your desk journal and a done signal.

## Validation owner
The orchestrator: it re-runs the harness, re-reads the diff, and hands the operator the copy
list and the in-client checklist.
