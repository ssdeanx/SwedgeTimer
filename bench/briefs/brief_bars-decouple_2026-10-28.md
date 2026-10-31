# Brief — bars-decouple (2026-10-28)

Desk: `bars-decouple`. Operator report, verbatim, on the current 2.1.3 tree:

1. "off hand should be same size as mh, and should only show when using it. also power bar
   should be below it."
2. "first of all ranged bar shouldnt be below mh/oh bar because thats where power bar
   should be for each class."
3. "ranged and melee are not the samething why are they effecting each other?"
4. "why is ranged bar popping up when im using melee..."
5. "u need to fix it so ranged isnt firing like that unless its actually being used."

Client context: operator plays TBC Anniversary (family TBC) and Classic Era (family ERA);
the build must keep working on every family the TOCs cover. No in-client session is
available to this lane — offline gate only, and say so.

## Write scope (hold it exactly — one writer per file)

- `main.lua`
- `bars.lua`
- `power_bar.lua`
- `config_presets.lua`
- `tests/bars_state.lua`
- `tests/power_bar_state.lua`

Do NOT touch: `classes/*`, `hunter_ui.lua` (owned by the parallel `hunter-tint` lane),
`Libs/`, any TOC, `main.lua`'s version line, `.luacheckrc`, `tests/run.sh`, `docs/`.

## Verified facts the lane must re-check itself before editing (read, do not assume)

- `main.lua` `handle_bar_visibility` / `set_bar_visibilities`: the `either` show
  condition calls `show_bar` whenever `self.in_combat` — a melee/combat state — so the
  ranged hand appears in every fight even when no ranged weapon is being fired.
- `power_bar.lua`: `choose_anchor` picks the offhand when it is *visible*, else the
  mainhand; `layout` re-anchors only when `pb.last_anchor ~= anchor` (frame identity),
  so the bar does not follow a melee bar that is moved/re-anchored after the first pass.
- `config_presets.lua` per-class hand blocks: warrior/rogue carry a ranged hand of
  200x15 at their own `y`; the shared defaults are 275x20 at y=-120/-142; hunter's
  mainhand/offhand are 200x14. Any collision in the operator's screenshot comes from
  these saved positions, not from a "second widget".
- `bars.lua` `configure_bar_size_and_positions(hand, width_override)` supports a width
  override only; there is no height override.

## Required outcomes

A1. The slot directly below the bottom-most melee bar belongs to the POWER BAR. No other
    hand may occupy it. The ranged hand keeps its own saved position; it is never
    re-anchored under the melee stack by this addon.
A2. Ranged hand visibility is driven only by ranged activity. It must not appear merely
    because the player is in combat. Show it while the ranged hand has a live cycle (or
    auto-repeat / a recent cycle), hide it when it has never fired or has been idle for
    more than a small number of cycles. It must not flicker between shots.
A3. Offhand: width and height equal to the mainhand's, for every class that has an
    offhand. It shows only while it is actually in use (live/recent cycle), not because
    combat started, and it disappears when idle.
A4. The hunter's thin MH/OH stack under the ranged bar is the hunter's own layout policy
    (owned by `hunter_ui.lua`, not this lane) — do not break it, and do not let it move
    the ranged hand or the power bar.
A5. The power bar follows its owning melee bar when that bar moves (detect a position
    change, not only a frame-identity change), and it sits below the offhand when the
    class has one, else below the mainhand.

## Rules

- Read `desks/journal.md`, `CAIRN.md` and `bench/lessons.md` first (bench-read).
- Read every file you edit before editing it.
- No git commands. No lint-config changes. Preserve file line endings.
- Every new user-visible toggle ships nil-safe (`== false` turns it off; nil = shipped
  default) and its default is documented in the class defaults.
- `bash tests/run.sh` must stay green (currently 54 steps, 0 failed; luacheck 2 warnings /
  0 errors in 97 files). Re-cut only pins your change genuinely invalidates, and say which.
- Report to `bench/bars_decouple_2026-10-28.md`: what changed (file:line), what was
  verified, what is UNVERIFIED in client, and any operator decision you had to leave open.
- Leave a `desks/bars-decouple/journal.md` (worked on / current state / next step).
