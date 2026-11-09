# Brief — layout-finish (2026-10-28)

Desk: `layout-finish`. Second wave of the 2026-10-28 bar work. The first wave landed
(`bars-decouple` + `hunter-tint`, gate 54/0). Operator's remaining orders, verbatim:

1. "the ranged bar for other melee classes should be moved."
2. "Also do client for all melee, i dont want ranged showing up on rogue sameway it does
   for warrior."
3. "off hand should always be same width as main hand. maybe have it so u can adjust the
   height for both."
4. "distance bar has nothing to do with mh bar. distance bar is just supposed to help me
   get exact or somewhat exact ... so i know when i am within actual melee range."
5. "/st diag works better, because it said there was no errors, meaning something was
   missed/silent."

## Write scope (hold it exactly — one writer per file)

- `main.lua`
- `bars.lua`
- `power_bar.lua`
- `config_presets.lua`
- `option_tables.lua`
- `option_table_presets.lua`
- `diag.lua`
- `tests/diag_state.lua`
- `tests/bars_state.lua`
- `tests/power_bar_state.lua`
- `tests/options_load_state.lua`

Do NOT touch: `classes/*`, `hunter_ui.lua`, `weave_range.lua` (the distance bar is
EXPLICITLY out of scope and must not be coupled to melee state), `Libs/`, TOCs,
`CHANGELOG.md`, `README.md` (docs lane follows), `.luacheckrc`, `tests/run.sh`.

## What the first wave already did (verify, do not redo)

- `main.lua`: ranged/offhand visibility is a "receipt" gate (a real shot/swing opens a
  window of 2 cycles); combat state alone no longer shows either hand.
- `bars.lua`: the offhand renders at the MAINHAND's width and height every layout pass.
- `power_bar.lua`: the row under the melee stack belongs to the power bar; the offhand row
  keeps the slot while idle.
- `config_presets.lua`: rogue/warrior ranged default y moved out of that slot — fresh
  profiles only. Saved positions are NOT migrated, so an existing profile still collides.

## Required outcomes

L1. The ranged hand is moved out of the power-bar row at RUNTIME for every melee class
    (WARRIOR, ROGUE, PALADIN, SHAMAN, DRUID and any other melee class the TOCs cover),
    not just for fresh profiles. A user's explicitly saved position must still be
    respected: only a position that is still the shipped default (or that demonstrably
    collides with the melee/power stack) may be re-placed, and the rule must be a stable
    one (no per-tick hopping, no fighting a drag).
L2. ROGUE behaves exactly like WARRIOR: ranged hidden unless actually used, and never
    sitting in the power-bar row. Verify the gate is class-agnostic, not warrior-shaped.
L3. Offhand width ALWAYS equals the mainhand width (keep the first wave's rule), and add
    ONE adjustable height for the melee pair: a class-level key that resizes the mainhand
    AND the offhand together, nil-safe (`== false`/nil = shipped default), documented in
    `config_presets.lua`, with an options widget next to the existing bar height control.
    Do not make the per-hand height options lie: hide/lock them or mark them as following
    the melee pair.
L4. `weave_range.lua` stays exactly as it is: the distance bar is a melee-range aid with
    its own progress bar, independent of the swing bars. Do not gate it on melee activity,
    do not move it, do not touch the file.
L5. `/st diag` gains a per-hand BAR STATE line so a silently misbehaving bar is visible
    without a client debugger: for each hand - built, shown, alpha, OnUpdate installed,
    start/speed/ends_at/now/progress, is_full, is_paused, engine_dead, vf_width, actual
    fill width, and the hunter queue-tint flags when the class exposes them. Print-only,
    nil-safe, capped like the existing report; update `tests/diag_state.lua`.
L6. Release honesty: the report must list what is proven offline and what needs a client.

## Rules

- Load and follow the lane skills first: `bench-read`, `desk-open` (desk `layout-finish`),
  `desk-journal`, finish with `signal-write`.
- Read every file you edit before editing it. Verify paths and line numbers yourself.
- No git. No lint-config changes. Preserve line endings.
- Version stays **2.1.3** — do not bump a TOC or `main.lua`'s version.
- `bash tests/run.sh` must stay green (54 steps, 0 failed; luacheck 2 warnings / 0 errors
  in 97 files). Re-cut only pins your change genuinely invalidates and list them.
- Report to `bench/layout_finish_2026-10-28.md`; journal at `desks/layout-finish/`.
