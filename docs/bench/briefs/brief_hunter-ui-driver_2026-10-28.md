# Brief — hunter-ui-driver (2026-10-28)

Desk: `hunter-ui-driver`. Closes audit finding **P2 / HU-37** — a real functional gap, not a
cosmetic one.

## The defect (exact chain, from the publish audit)

The hunter visual set — cast bar, cast zone, range helper, Rapid Fire bar, pet badges, OOM
Viper, LnL badge, trap badge, aspect icon — is **parented to the ranged bar frame and ticked
from its OnUpdate**. The 2026-10-28 activity gate hides the ranged bar when no shot has
landed for two cycles (and it is never shown when Auto Shot is not armed). A hidden frame
runs no OnUpdate, so:

> Auto Shot not armed + no shot inside the window ⇒ ranged bar hidden ⇒ its child visual set
> never ticks ⇒ a **Steady Shot / Volley cast with Auto Shot off gets no cast bar at all.**

`hunter_ui.lua` (:1606, :1649-1666) drives the set from the ranged tick, and
`ranged_bar_ready` (:163-165) ignores the activity gate, so the set believes it is ready
while nothing paints. (Hidden-frame-runs-no-OnUpdate is client semantics — offline we can
only prove the wiring, not the render.)

## Required outcome

Decouple the hunter visual set from the ranged bar's visibility: it must tick from a
**hunter-owned driver that is always eligible** (its own OnUpdate on a never-hidden frame, or
an equivalent already-existing always-running hook), so a cast, a proc badge or the range
helper still paints when the ranged bar is hidden. Keep the FIRST-WAVE contract intact: the
set stays a silent no-op while the ranged hand is disabled or absent (Retail must stay
inert), and it must not resurrect the ranged bar itself (the activity gate owns that).

Do not re-parent the widgets if a driver-only fix is sufficient; prefer the smallest change
that makes the tick independent of the ranged bar's visibility. If re-parenting is
unavoidable, keep every anchor/width the same as today.

## Write scope

- `hunter_ui.lua`
- `tests/hunter_state.lua`

Nothing else: no `main.lua`, `bars.lua`, `option_tables.lua`, `diag.lua`, `classes/*` (other
lanes are editing those right now), no TOCs, no docs, no `Libs/`.

## Proof required

- A pin that proves the visual set ticks while the ranged bar is hidden (feed the driver, not
  the ranged hand).
- The existing inert paths still pinned: Retail / no ranged hand ⇒ no-op; disabled ranged
  hand ⇒ silent.
- The set still tracks the ranged cycle when the bar IS visible (no double tick, no
  duplicate repaint).
- Red-first mutation: revert to the ranged-tick-only wiring and show the new pin fails.

## Rules

- Load and follow the lane skills first: `bench-read`, `desk-open` (desk `hunter-ui-driver`),
  `desk-journal`, finish with `signal-write`.
- Read every file you edit before editing it.
- No git. Preserve line endings. **Version stays 2.1.3.**
- `bash tests/run.sh` must stay green (54 steps / 0 failed; luacheck 2 warnings / 0 errors in
  97 files). List any pin you re-cut.
- Report to `bench/hunter_ui_driver_2026-10-28.md`; journal at `desks/hunter-ui-driver/`.
- State what still needs a live client.
