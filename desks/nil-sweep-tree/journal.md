# nil-sweep-tree — Journal

## 2026-10-22 — Desk opened
- **Purpose:** final full-tree nil sweep (last lane of the release wave) across every shipped module EXCEPT classes/*.lua (already done: desks/swing-nil-sweep, 41 fixes / 50 legs). Classify every per-frame/per-event index chain GUARDED or UNGUARDED; fix UNGUARDED with the file's own guard idiom.
- **Scope:** hud.lua, practice*.lua, main.lua, bars.lua, compat.lua, option*.lua, config*.lua, design(mode).lua, nextaction_ui.lua, hunter_ui.lua, rotationtext.lua, ldb.lua, diag.lua, utils.lua + remaining shipped root modules. Off-limits: classes/*.lua, run.sh, Libs/, TOCs, versions.
- **Context in:** desks/journal.md lane table; desks/swing-nil-sweep/journal.md (method template); bench/swing_display_2026-10-22.md; hands-up HU-15/HU-22/HU-29.
- **Next step:** enumerate shipped files from TOCs, locate per-frame/per-event entry points, classify chains, fix + leg + mutate.

## 2026-10-22 — Sweep complete, awaiting orchestrator reconcile
- **Worked on:** all 38 shipped root modules (TOC authority), every per-frame entry
  (bars OnUpdate, hud/practice/rotationtext/nextaction driver OnUpdates, weave/enemy
  drivers, 0.05 s range + aura polls, 0.2 s weave poll) and per-event entry (40 main.lua
  AceEvent handlers, 6 lib callbacks, frame OnEvent, class hooks, cast/drag/options
  events). 31 guard sites in 8 modules: main.lua 17 (accessors, enable check, activate,
  post_init lock, CLEU, rage, spellcast handlers, form flag, bar-enable/visibility/set-
  visibilities, three class helpers, two spellcast handlers, post-init hook), practice_ui 2 (cast_key AW read,
  save_position), weave_range 1, designmode 2 (enter gate, bar reset), hunter_ui 3
  (build/update/sync), hud 3 (init/on_bar_update/on_update), rotationtext 1, nextaction_ui
  2. Report: bench/nil_sweep_tree_2026-10-22.md (per-file verdicts + before/after).
- **Current state:** all fixes are no-ops when their table/frame exists. 8 owning suites
  green: main_init 1047, practice_ui 2542, weave_range 151, designmode 670, hud 844,
  rotationtext 246, hunter 1794, guide_contract 1057; regression bars_state 935 /
  options_load 3501 / practice_state 1533 green. luacheck on 8 touched files 0/0; repo
  floor unchanged at 2 warnings / 0 errors in 90 files. 27/27 mutations killed on fresh
  /tmp/opencode copies (removed); 2 legs strengthened after short-circuit findings
  (N10 nil class token, HU2 cast bar visible). Line endings byte-verified per file.
- **Next step (orchestrator):** full run.sh + commit (commit stays yours). My diff is
  main/practice_ui/weave_range/designmode/hunter_ui/hud/rotationtext/nextaction_ui +
  8 suite leg sections + this bench/desk trail. UNVERIFIED in-client: unsupported-class
  paths, explicit class_activation switch, design-mode refusal (U1 in the bench report);
  plus two pre-existing observations filed there (U2 result-font guard, U3 lowercase
  player_class at option_tables load).

## 2026-10-22 — Follow-up: warrior_state CLEU dispatch pins recut (orchestrator-found)
- **Worked on:** tests/warrior_state.lua only. The G2 dispatch pins still matched the
  pre-sweep literal `self.PALADIN./self.WARRIOR.on_combat_log_unfiltered(self, event, ...)`
  strings; fix #6 replaced those with the selected-class presence guard, so the pins failed
  2 of 2096. Recut both pins (never deleted): they now require
  `local class = self[self.player_class]` -> `type(class) == "table" and
  class.on_combat_log_unfiltered` -> `class.on_combat_log_unfiltered(self, event, ...)`,
  plus a new order pin (neutral pre-pass before dispatch) and a negative pin (no direct
  PALADIN/WARRIOR naming). Init-guard pin untouched.
- **Current state:** warrior_state 2098 checks PASS (+2: 3 old checks -> 5 contract
  checks); main_init_state 1047 PASS; luacheck tests/warrior_state.lua 0/0. Red-first
  mutation on a /tmp/opencode copy (handler reverted to the direct-call shape) fails
  exactly the 4 new contract pins; copy removed. Repo luacheck floor unchanged.
- **Next step (orchestrator):** re-run full run.sh and commit. The bench report's
  validation paragraph is superseded for warrior_state by this entry (2098, not 2096).
