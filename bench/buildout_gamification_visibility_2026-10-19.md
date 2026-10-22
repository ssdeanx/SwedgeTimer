---
name: buildout-gamification-visibility
date: 2026-10-19
lane: gamification-visibility
scope: final-completion-plan Phase 4 - the practice gamification's visible surface
  (the panel's level badge + session XP bar and the level-up / achievement chat
  notices) ships ON for a fresh profile.
---

# Gamification visibility — the badge, the XP bar and the notices ship ON

Plan source: `bench/final_completion_plan_2026-10-19.md` (Phase 4).
Design source: `bench/buildout_practice_gamification_hook_2026-10-19.md` (§"The
panel badge (opt-in, OFF by default)" and §"Open / filed for the operator" item 1 —
the default-flip request this lane applies).

## The gate

The operator explicitly asked for visible practice levels/XP — "start at lvl 1, gain
xp each practice, level up". That request **is** the gate for this default-visible
change, and it is recorded in the code next to the default it gates (the standing rule
is "no default-visible change without an operator gate").

## What landed

| File | Change |
| :--- | :--- |
| `config_presets.lua` | `ST.class_defaults.practice_panel_badge = true` (+ the gate comment) |
| `tests/options_load_state.lua` | NEW section 24 — the behavioural pins (129 checks) |

No other file was touched: `practice_ui.lua` (a sibling lane owns it), `practice.lua`,
`practice_progress.lua`, `practice_stats.lua`, `option_tables.lua`, the class files,
`main.lua`, `diag.lua`, `compat.lua`, `hud.lua`, `bars.lua`, `tests/run.sh`, the TOCs,
the versions, README, CHANGELOG, docs. No git, no lint-config change, no `Libs/` touch.
Line endings (LF) preserved in both touched files.

## The default

`ST.class_defaults` is the AceDB default for every class table (`config.lua`:
`profile['**'] = ST.class_defaults`, and AceDB's `copyDefaults` fills the class table
from it). The key therefore reaches a FRESH profile of every class:

* a fresh profile → `db.practice_panel_badge == true` → the badge, the XP bar and the
  notices are visible;
* a profile that saved `false` → the saved value wins over the default → still off;
* an old profile with NO key → the read is `== true` (nil = off) → still hidden.

The read is nil-safe in `practice_ui.lua` (`ui.badge_is_enabled`: `db.practice_panel_badge
== true`) and the write is `ui.set_badge_enabled`. The chat notices ride the SAME key:
`announce()` returns early when `ui.badge_enabled` is false, and `ui.badge_enabled` is
the value `ui.badge_is_enabled` read at the session start — so with the badge off the
progression still runs and still saves, silently.

## The pins (`tests/options_load_state.lua` section 24)

The pins are **behavioural**, not textual. A mini sandbox loads the REAL
`practice_stats.lua` + `practice_progress.lua` + `practice_ui.lua` (the two pure
modules and the live hook module — no WoW API, no frames) and drives the real session
path (`begin_progress_session` → `record_progress_attempt` → `end_progress_session`),
so the notice gate is exercised end to end, not by pattern-matching the source.

| Group | Pins |
| :--- | :--- |
| (a) the default | the key ships `true` in `ST.class_defaults`; it is the ONLY default it carries in `config_presets.lua`; the operator order is named as the gate inside the block; `config.lua` hands the shared defaults to every class table through AceDB's `'**'` section |
| (b) the merge | for all TEN class tokens: a fresh profile has the badge ON, a profile that saved `false` keeps it OFF, and no class table overrides the shared default |
| (c) the widget | the badge's read/write entry points exist, the toggle ROUND-TRIPS (write → class table → read, both directions), the badge frame carries its four readouts (level / xp / bar_fill / session), and the module rides exactly ONE db key |
| (d) the notices | with no key at all → no chat notice; with the key `false` → no chat notice; with a fresh profile → the level-up notice fires; with an `S` → the achievement notice fires; with the key `false` → the achievement notice does NOT fire |

## Verification

* `lua5.1 tests/options_load_state.lua` → **3380 checks, 0 failed** (the section adds
  129).
* `bash tests/run.sh` → **41 steps, 0 failed**; luacheck **2 warnings / 0 errors** in
  83 files — the floor (the two warnings are `compat.lua` and `main.lua`, both
  KEEP-ruled, not this lane's files). `luacheck config_presets.lua
  tests/options_load_state.lua` → **0 warnings**.
* **mutation proofs: 5/5 killed** on `/tmp/opencode/gamvis-mut` (script
  `/tmp/opencode/gamification_visibility_mutations.py`):

| Mutant | Result |
| :--- | :--- |
| M1 "default removed" (the line deleted from `config_presets.lua`) | killed — 16 pins failed |
| M2 "default false" (flipped the wrong way) | killed — 16 pins failed |
| M3 "notice ignores the toggle" (`announce` loses its gate) | killed — 3 pins failed |
| M4 "nil-safe read broken" (`== true` → `~= false`) | killed — 1 pin failed |
| M5 "the toggle write is dead" (`set_badge_enabled` stops writing) | killed — 2 pins failed |

## Crossfire seen (NOT this lane's files)

* A transient third luacheck warning appeared in `tests/smoke.lua:828` during the
  first harness run — the file was being written by the sibling `compat-f4` lane at
  that moment (mtime 22:41:30, after this lane's last edit). Re-running luacheck on
  the settled file: **0 warnings**; the final harness run holds the 2-warning floor.

## Open / filed

1. **No options widget exists for the toggle.** `practice_panel_badge` appears NOWHERE
   in `option_tables.lua` / `option_table_presets.lua` (grep: 0 hits) — the Progress
   page (step 3) ships a read-only page whose widgets carry no `get`/`set`
   (`option_tables.lua:657-669`). The hook lane filed the widget as the Progress page's
   job; that page never carried it. Consequence: with the default ON there is **no
   in-game way to turn the badge off** — only a SavedVariables edit or
   `/st`-level db write. The round-trip pins therefore exercise the module entry
   points (`st.practice_ui.set_badge_enabled` / `badge_is_enabled`), which is exactly
   the surface an options widget would call. `option_tables.lua` was out of this
   lane's scope, so the widget was NOT added here. **Filed as HU-9 for the operator.**
2. **A stale pin label in a sibling suite (cosmetic).**
   `tests/practice_ui_state.lua:3632` still reads "the badge is hidden by default".
   The PIN is still correct — that suite's fixture class table deliberately has NO
   `practice_panel_badge` key, so it pins the nil-safe read (nil = off), which the
   default does not change. Only the LABEL is now misleading. That file was out of
   this lane's scope; the owner of the file may reword it.
3. **In-client behaviour is UNCONFIRMED**, like every offline pin: the badge's
   rendering on a fresh profile and the level-up notice in the chat frame have not
   been observed in a client.
