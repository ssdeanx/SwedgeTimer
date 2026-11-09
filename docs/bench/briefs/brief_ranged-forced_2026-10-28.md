# Brief — ranged-forced (2026-10-28)

Desk: `ranged-forced`. Operator ruling, verbatim: **"it should stay with the rest, aka the
new way."**

That closes the question the `layout-finish` lane left open (its U2 blind spot): the
ranged placement rule must apply the NEW layout to every class that owns a ranged hand,
**even when the saved row was dragged or scaled**. A legacy saved position does not win.
The power-bar row directly under the melee stack is never given up.

## Write scope

- `bars.lua` (the ranged placement rule)
- `tests/bars_state.lua` (the placement pins)

Do NOT touch: `config.lua`, `tests/appearance_defaults_state.lua` (the `appearance-fix`
lane owns those right now), `classes/*`, `hunter_ui.lua`, `weave_range.lua` (the distance
bar is out of scope and must stay uncoupled), `Libs/`, TOCs, `CHANGELOG.md`, `README.md`,
`.luacheckrc`, `tests/run.sh`.

## Current state (verify by reading, do not assume)

The login-time rule added today (`ST:migrate_ranged_placement`, `bars.lua`) only acts while
the ranged row is still exactly a shipped default (`x=0`, `point=CENTER`, `scale=1`, `y` in
the shipped set) AND demonstrably intersects the melee stack + power-bar band. A dragged or
scaled row is deliberately skipped. Your job is to remove that skip.

## Required outcomes

R1. Every class that owns a ranged hand gets the ranged row placed above the melee stack and
    the power-bar band on login — dragged rows, scaled rows and default rows alike. The
    class's shipped row is used when it already sits above the band; otherwise the row is
    placed just above the band (2 px gap, honouring the power bar's clamped height).
R2. Idempotent and quiet: once placed, no repeat writes, no per-tick work, no geometry
    hopping, and at most one announcement per class per session.
R3. Fresh profiles keep the shipped default (the migration must not double-write them).
R4. The pins that encode "a drag wins" are replaced by pins that prove a dragged row and a
    scaled row are both moved to the new layout, and that a second run does nothing.
R5. Classes with no ranged hand keep reporting/behaving as "no ranged" (paladin, shaman,
    druid own no ranged hand).

## Rules

- Load and follow the lane skills first: `bench-read`, `desk-open` (desk `ranged-forced`),
  `desk-journal`, finish with `signal-write`.
- Read every file you edit before editing it.
- No git. No lint-config changes. Preserve line endings. Version stays **2.1.3**.
- `bash tests/run.sh` must stay green (54 steps, 0 failed; luacheck 2 warnings / 0 errors in
  97 files). List every pin you re-cut and why.
- Report to `bench/ranged_forced_2026-10-28.md`; journal at `desks/ranged-forced/`.
- State what still needs a live client (the drag-then-login behaviour on the operator's own
  profile is the key one).
