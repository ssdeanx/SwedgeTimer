# Hunter practice + designer — build record 2026-10-19

Desk: hunter-practice-designer. Objective: hunter drill starts/runs/grades through
the existing Practice Mode flow (options toggle + `/st practice` → single session
flow, panel icons cast simulated spells), plus designer coverage for every hunter
element. Validation owner: orchestrator.

## Archive pattern (operator-ordered, read don't guess)

`docs/swedge/SwedgeTimer_TBC` and `docs/swedge/SwedgeTimer_Forever` are
file-identical (cmp-clean: practice.lua, core.lua, settings_ui.lua, editmode.lua,
import_export.lua, main.lua, hud.lua, nextaction.lua; identical file lists) — one
pattern, three runtimes (Era classic API, TBC Anniversary classic API, Forever
Mainline-code client). Patterns found and followed:

1. Practice page is class-agnostic: `{ id = "practice", group = "Guides &
   Practice" }` with tabs (Simulation / Rotation & Timeline / Feedback), listed for
   ALL classes (settings_ui.lua). Followed: hunter options entry mirrors the
   archive `practice_toggle` widget shape exactly (execute, Start/Stop Practice
   name, func → session toggle); the drill is discoverable class-agnostically via
   `scenarios_for_class("HUNTER")`. The top-level Practice tab itself is the
   practice-every-class lane's build; this lane plugs the hunter drill into it.
2. Both-ways start: `/st practice` → session toggle (core.lua:172-177); options
   Start/Stop → session toggle + NotifyChange (core.lua:948-965). Followed: hunter
   starts through the SAME `st.practice_ui.toggle` from both callers (main.lua
   slash and options func unchanged); hunter options widget func routes to
   `st.practice_ui.toggle(ST)` — no new invocation.
3. Session: toggle → start/stop; start hooks + active, fight begins on Start Fight
   (archive: "wait for Start Fight"); current port auto-begins the fight with the
   session (documented phase-2 decision, practice_ui.lua header). Followed the
   CURRENT tree: hunter drill begins its windows run in start, re-begins on Start
   Fight. Tree wins over archive (stated reconciliation).
4. Panel icons cast simulated spells; keybinds configurable (archive
   practice_key_* db-persisted + import_export support; current port session-local,
   documented deferral). Followed current tree: hunter shots session-local, start
   unbound, same capture/rebind flow, same order-swap branches.
5. Grading/feedback: TWIST!/MISS + timeline + score/bests (archive); S–F grades +
   shared accumulator (current). Hunter: shell S–F grades into the shared
   `ui.score`/bests + MOVE! window cue through the shared result popup.
6. Designer: editmode ELEMENTS (bar, seal icons, success text, NAG, HUD, rotation
   text, virtual effects, practice_rotation, practice_timeline), available-gated on
   active, db-backed save. Current port: bars/HUD/rottext/NAG/practice panel +
   delegated rotation/timeline (session-local). Hunter audit below.
7. Real-combat pause + deadline shift (current port). Hunter: same pause, windows +
   fight start shift (practice_shift_pause mirrors shift_sim_times).
8. Archive practice is paladin-only (no "hunter" in practice.lua) — the hunter
   drill is new, built from the registry shell (hunter_forced_move) + H2 shot
   analytics + prepull/weave checklists already in current practice.lua.

## API verification (per client branch, read-only `git show`)

Touched WoW surface adds ZERO new APIs (all calls exist in the current tree's
practice path, which ships on all flavors). Confirmed present on Era
(classic_era), TBC Anniversary (classic_anniversary) and Forever
(origin/forever):
- BackdropTemplate + CooldownFrameTemplate: Blizzard-owned XML on all three
  (AchievementUI/ActionBar XMLs).
- SetOverrideBindingClick: RestrictedFrames.lua on all three (+ GamepadShared on
  Forever).
- InCombatLockdown, GetSpellInfo: Blizzard_APIDocumentationGenerated on all three.
- practice_ui.lua in 7/7 TOCs.
- Drill logic calls only st.practice.harness (own), api.get_family_spell_id /
  api.get_time / api.GetSpellInfo (compat shims, already used by the hunter
  module on all flavors). No new event registrations, no combat-log reads
  (Forever-safe), no family branches (family-independent — one code path on all
  three runtimes).

## Files changed

- `classes/hunter.lua` (CRLF kept): drill section (PRACTICE_SCENARIO_KEY /
  PRACTICE_SHOTS / PRACTICE_SHOT_ORDER, lookups, harness wrappers, status/clock/
  shift helpers) + post_init `practice_ui.init` (guarded, idempotent).
- `practice_ui.lua` (CRLF kept): hunter-keyed branches only — routing predicate,
  shot def/name helpers, panel title/grid/paladin-widget skips, keybind order
  swaps, hunter session helpers, start/stop/toggle_fight/start_fight/stop_fight/
  tick/cast/sync/clear/info/button/hint/timer/result branches. Paladin path
  behaviour-identical (branches select, never reimplement).
- `option_tables.lua` (LF kept): HUNTER 7.6x Practice header + desc + toggle
  (mirrors the archive/paladin Start/Stop shape, same invocation target).
- `tests/hunter_state.lua` (LF kept): sections P (shot table), Q (icon ids), R
  (session lifecycle through the real shell), S (post_init wiring), T (Era/TBC/
  Forever matrix), U (designer coverage). No other test file touched.
- `practice.lua`, `designmode.lua`: READ, untouched (shell already complete;
  registry already covers hunter's five elements).

## Validation

- `bash tests/run.sh` → my scope green: hunter_state 969, hunter_guide_state 1195,
  practice_state 1208, practice_ui_state 863, plus luac5.1/smoke/bars/hud/
  rotationtext/diag/main_init/toc all green; luacheck 0 errors, 0 warnings in my
  files. Full-tree 38 steps / 4 failed — ALL four are concurrent-lane crossfire
  in files outside this lane's scope (verified hunk-by-hunk, none authored here):
  designmode_state registry count (sibling seal_icons/success/pips descriptors),
  options_load_state 6 SODOPT shaman pins (sibling expectations), wiring_check
  druid/rogue/shaman dead hooks + main.lua accepted defects (sibling APIs awaiting
  central routing), shaman_state flaky mid-edit (passes solo, 589). Reconcile owns.
- `lua5.1 tests/hunter_state.lua` → 969 checks green (P+Q+R+S+T+U).
- Mutation proofs on /tmp/opencode/mut_hunter (backups, mutate real, run, restore,
  cmp byte-identical after each):
  1. practice_cast idle-gate strip → NO KILL (shell's scenario_event double-gates;
     kept as API-boundary contract with rationale).
  2. spell-id fallback (nil → 56641) → KILLS (unknown-hides pins).
     **NOTE 2026-10-20 (desk `corpus-corrections`):** 56641 is the **WotLK**
     Steady Shot rank-1 — it **does not exist on the TBC client** and the
     **Forever client has no Steady Shot at all** (the spell arrived in 2.3;
     the TBC APL casts 34120 r1). The fallback id itself is untouched by this
     desk (it is the shipped tree's business); the note is here so no future
     lane reads 56641 as a TBC/Forever spell id. Evidence:
     `bench/hunter_apl_utility_build_2026-10-20.md` §3;
     `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **H3**/**H4**.
  3. routing forced true → KILLS (paladin suite breaks; routing load-bearing).
  4. shift-guard strip → KILLS (NaN corrupts windows).
  5. post_init guard strip → KILLS (absent module throws).
  6. scenario-key drift → KILLS (accessor + designer pins).
- `git diff` holds hunter-keyed regions only in shared files (hunk audit: every
  added line is hunter-gated or a documented paladin-identical branch; sibling
  shaman/warrior/paladin lines in the same files untouched — the shaman lane
  edits practice_ui.lua concurrently and extends my guard lines with its own
  conjuncts; coexistence verified, suites green on both sides).
- Line endings kept (classes/hunter.lua + practice_ui.lua CRLF, option_tables.lua
  + hunter_state.lua LF); touched-lines whitespace only; no commits; no invented
  ids; no new WoW APIs (client-branch verification cited above).

## Designer audit (diffed vs archived ELEMENTS)

| Hunter element | Registry descriptor | Verdict |
|---|---|---|
| mainhand/offhand/ranged bars | bar_mainhand/bar_offhand/bar_ranged | WIRED (generic, class-agnostic) |
| Cooldown HUD | hud (+ HUD_SLOTS/provider) | WIRED (pins U) |
| Rotation label | rottext (+ get_rotation_key) | WIRED (pins U) |
| Next Action Guide | nag (+ guide/gather/evaluate) | WIRED (pins U) |
| Practice panel | practice_panel (available = is_active) | WIRED for hunter sessions (this lane: hunter sessions set is_active) |
| Cast bar / range helper / RF bar / aspect icon / badges / cast zone / target warning | — (bar children) | COVERED by doctrine: children of the ranged bar frame, move with the bar_ranged overlay (designmode.lua header; archive `fixed`/fixed_hint precedent) |
| Shot report frame | — | FILED (see below) |

## Filed follow-ups (need files outside this lane's scope)

- F1 hunter_report descriptor: the shot report frame (practice_ui.lua
  build_hunter_report, UIParent-anchored CENTER 0,60, movable, session-independent)
  has no designmode descriptor. Spec for the owning lane: key
  `"hunter_report"`, title `"Hunter shot report"`, get_frame →
  `st.practice_ui.hunter_report_frame`, available → visible flag, save moves the
  live frame session-locally (rotation/timeline precedent, no db keys), reset →
  CENTER 0,60. Needs `tests/designmode_state.lua` count 9→10 + registry order —
  owned by the designer-every-class lane with its reconcile. Reason: count pin +
  registry order are central-lane owned; this lane must hand off green.
- F2 top-level Practice tab: the tab itself is the practice-every-class lane's
  build; this lane verified the hunter plug-in surface (registry discovery +
  options entry + routing branches) and hands off the contract.
- F3 keybind defaults for drill shots: shots start unbound (capture flow
  assigns); any shipped defaults belong to a future options pass with user
  research, not invented here.

## In-client confirmation owed (UNCONFIRMED, owner test session)

Drill grading on a live client; shot icon textures per family (blank until the
client spell data answers); panel layout beside the hunter bars; report numbers
against real fights. TESTING.md checklist covers the session; nothing here is
presented as live-tested.
