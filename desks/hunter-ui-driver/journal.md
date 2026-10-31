# hunter-ui-driver — Journal

## 2026-10-28 — Desk opened (HU-37 / audit P2)
- **Purpose:** decouple the hunter visual set (cast bar, cast zone, range helper, Rapid
  Fire bar, pet/OOM/LnL/trap badges, aspect icon) from the ranged bar frame's OnUpdate, so
  a cast/proc/range reading still paints while the activity gate hides the ranged bar.
- **Scope:** `hunter_ui.lua`, `tests/hunter_state.lua` only. Other lanes own
  option_tables/diag/main/power_bar right now. Version stays 2.1.3; no git; no docs.
- **Brief:** `bench/briefs/brief_hunter-ui-driver_2026-10-28.md`.
- **Next step:** read hunter_ui.lua + the hunter_ui sandbox in tests/hunter_state.lua,
  then wire a never-hidden hunter-owned driver and pin it.

## 2026-10-28 — HU-37 landed (audit P2): the visual set no longer rides the ranged bar's tick
- **Worked on:** replaced the ranged-bar-only tick with a hunter-installed hook on the hand's
  anchor frame (`hunter_ui.lua:233-367`; claimed in build at `:671`). The widgets now parent
  to that never-hidden frame while EVERY anchor/width still reads the ranged bar frame; the
  bar's own tick keeps the frame while it is visible (`ranged_tick_is_live` defer at
  `:262` -> no double tick) and the anchor tick takes every frame it cannot run. `ui.update`
  gained the configured-visibility gate (`ranged_ui_allowed` `:194`, used `:1835`): class /
  spec / hand enable + (only while the bar is hidden) the hand's show rule; the ACTIVITY
  gate is deliberately ignored. H3 guard around the whole tick (:338-367). Lazy OOM/LnL/trap
  badges parent to the host.
- **Why the anchor frame instead of a new driver frame:** a 7th build-time hunter frame
  breaks the frame census at `tests/bars_state.lua:1059` (reproduced: got 21, want 20), and
  that file is outside this lane's write scope; the lazy-badge precedent says do not move
  that reconcile-owned pin from here. Follow-up: hoist a dedicated
  `SwedgeTimerHunterUIDriver` frame + bump HUNTER `extra_frames` 6 -> 7; `ui.poll`/
  `tick_once` move unchanged.
- **Current state:** `bash tests/run.sh` 54 steps / 0 failed; luacheck 2 warnings / 0 errors
  in 97 files; `tests/hunter_state.lua` 2040 checks (new §14n / §14n-i / §14n-ii, NILSWEEP
  HU2 re-cut). Red-first on a /tmp copy: M1 (back to ranged-tick-only) kills the hidden-bar
  cast/helper/badge pins (104 checks); M2 (both tick sources) kills the no-double-tick pin.
  Report: `bench/hunter_ui_driver_2026-10-28.md`.
- **Next step:** operator in-client pass (report §"What still needs a live client"): cast with
  Auto Shot off while the bar is hidden, auto-repeat transitions, proc badges / range helper,
  strata + draw-level + drag, class switch-off, Retail inert, `/st diag` clean.

## 2026-10-28 — [signal:done] HU-37 decouple landed and pinned
- Gate green (54/0, luacheck 2/0), report on the bench, two files changed, brief scope held.
