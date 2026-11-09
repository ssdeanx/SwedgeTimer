# Brief — widgets-guard (2026-10-28)

Desk: `widgets-guard`. One latent defect, found by the `appearance-fix` lane's AceDB sweep
and confirmed by reading the code.

## The defect

`widgets.lua:44-46`:

```lua
channel = class_db and class_db.sound_channel
channel = channel or ST.db.profile.sound_channel
```

Both keys are absent from most class rows and from the profile root, and the profile/class
tables carry AceDB's `'**'` defaults metatable (`Libs/AceDB-3.0/AceDB-3.0.lua:88-107`),
which CREATES and rawsets a defaults table on a missing-key read. The read therefore
returns a truthy TABLE, which is handed to `PlaySoundFile` unpcall'd.

Currently unreachable (the two sound-preview dropdowns live only on the paladin panel, and
PALADIN ships a string `sound_channel`), so this is a latent trap, not a live failure —
but it is the same class of silent defect as the appearance migration, and this build is
meant to be publishable.

## Write scope

- `widgets.lua`
- the single test suite that covers it — identify it yourself (search `tests/` for the
  widget/sound path) and name it in your report.

Nothing else. Do not touch `config.lua`, `bars.lua`, `tests/bars_state.lua` (other lanes
own those right now), `Libs/`, TOCs, docs, `.luacheckrc`, `tests/run.sh`.

## Required outcomes

W1. The channel read never triggers the defaults metatable and never yields a table:
    `rawget` both sources, require `type(channel) == "string"`, and fall back to the
    shipped default when nothing usable is stored.
W2. `PlaySoundFile` (and any sibling sound call in that path) is pcall-guarded, so a bad
    channel can never throw out of a dropdown preview.
W3. A test proves the trap: with a `**`-metatable profile and absent `sound_channel`, the
    read returns the default string and the sound call receives a string (never a table).
W4. Sweep `widgets.lua` for the same plain-read-of-a-possibly-missing-key pattern and fix
    any siblings inside your scope; list anything outside it.

## Rules

- Load and follow the lane skills first: `bench-read`, `desk-open` (desk `widgets-guard`),
  `desk-journal`, finish with `signal-write`.
- Read the file before editing it. No git. No lint-config changes. Preserve line endings.
- Version stays **2.1.3**.
- `bash tests/run.sh` must stay green (it is RED mid-flight because another lane is editing
  `bars.lua`/`tests/bars_state.lua` — run YOUR suite plus the gate, and if the gate is red
  only in that lane's placement pins, say so explicitly and do not "fix" their pins).
- Report to `bench/widgets_guard_2026-10-28.md`; journal at `desks/widgets-guard/`.
