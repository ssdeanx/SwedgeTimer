# Druid Practice + Designer — Journal

## 2026-10-19 — Desk opened
- **Purpose:** FULLY implement practice + designer for DRUID on the existing flows.
- **Scope:** `classes/druid.lua`, `tests/druid_state.lua` owned; `option_tables.lua`,
  `practice_ui.lua` druid-keyed regions only. No other classes, no Claw changes,
  no commits, no lint-config changes.
- **Invocations (operator-ordered):** practice starts from the options Practice toggle
  (same toggle pattern as paladin); the panel-icon session flow is unchanged and shared.
  `/st practice` untouched. No new invocation pattern, no new practice flow.
- **Next step:** implement druid seams (post_init practice_ui.init, practice_sync,
  harness routing wrappers), DRUID options toggle, practice_ui druid-safe sync/restore
  branches, designer + practice pins in druid_state, harness + mutations, signal done.

## 2026-10-19 — Practice + designer built, pinned, proven
- **Worked on:** druid practice seam + DRUID options Practice entry + bridge hardening + designer gap audit + pins.
  - `classes/druid.lua`: post_init now inits shared `practice_ui` (guarded, paladin-mirror); new
    `practice_sync` (returns 0, no seal state to mirror); harness wrappers
    `practice_scenario_key/new_practice_session/tick_practice_session/practice_shift/practice_summary/end_practice_session`
    (nil-safe, degrade to nil/0/false); stale "paladin-only" comment corrected.
  - `option_tables.lua` (DRUID section only): full port page-shape Practice entry — header, desc,
    Start/Stop toggle (same `practice_ui.toggle` both-ways start), weapon-speed override, result
    duration/size/colors, panel X/Y + reset (same keys/rows the session reads, paladin-mirrored).
  - `practice_ui.lua` (2 druid-gated branches): sync uses `DRUID.practice_sync` on druid;
    restore skips `PALADIN.on_aura_change` on druid. All other classes byte-identical.
  - `designmode.lua`: read fully, zero edits — audit vs archive ELEMENTS (TBC≡Forever, cmp-clean):
    every druid-created element (mainhand bar, HUD, rottext, guide, practice panel/rotation/timeline,
    pips via self-registered `druid_pips` key) already positionable; seal icons/success text are
    paladin-only, effects is virtual — correctly absent. No gap to close.
  - `tests/druid_state.lua`: sections 30-35 (602 checks PASS) — sync/init, nil-degradation, drill
    end-to-end via harness (S+C=70 scoring), options+bridge text pins, designer coverage pins,
    family matrix Era/TBC/Wrath/Forever (projects 2/5/11/18).
- **Verified:** archive pattern reconciled from direct diffs (8 files identical; practice page shape,
  both-ways start, session mechanics, 9 ELEMENTS, import_export deferral, sim defaults 0.8/28/colors).
  wow-ui-source per-branch: C_Timer.After + InCombatLockdown documented on classic_era,
  classic_anniversary, origin/forever; my diff adds zero bare WoW globals (all internal calls);
  SetOverrideBinding* guarded by existence probe in pre-existing code. 5/5 mutations kill with
  byte-identical restores (proofs on /tmp/opencode copies, since removed). luacheck 0/0 on my 4 files.
- **Current state:** my scope green (druid_state 602/602, syntax, luacheck floor). Tree reds are
  parallel-writer crossfire, none mine: wiring_check 21 dead-hooks (druid 5 + hunter 9 + rogue 7 —
  per-class wrappers awaiting the still-running practice-every-class routing lane; rogue/hunter same
  pattern); options_load_state SODOPT shaman asserts; designmode_state registry 9-vs-11 (another lane
  added 2 elements); practice_ui HINT_SHAMAN_* warnings; paladin_state flap. druid FAILs: zero.
- **Next step:** orchestrator reconcile — routing lane lands callers for the per-class wrappers
  (wiring_check), design-registry count pin update, then publish. No operator action needed from this desk.
