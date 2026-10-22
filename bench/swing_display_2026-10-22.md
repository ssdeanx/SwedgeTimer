# Swing display lane (2026-10-22): ranged shared state + lazy-bars home

Desk `swing-display` (ses_e9b0ee364ffez1Y1QmPOsCqJlH). Scope: bars.lua,
classes/hunter.lua, hunter_ui.lua (+2 test files re-cut). Untouched: main.lua,
compat.lua, swing_source.lua, run.sh, vendored Libs, TOCs, versions, options.

Reference (read-only, compared not lifted): /home/sam/SuperSwingTimer-WoW/ —
IsAutoShotSpell matches id OR name with English fallback; hidden-window cache
cleared on every StartSwing, cached only while `now` is inside; ranged bar
shows swing progress, cast bar shows live-cast-or-hidden-window; hunter MH
hidden while ranged active/cast visible (reference policy, not a defect).

## Symptom verdicts

1. Mainhand bar never appears, ANY class — NOT FIXED by this lane (no START
   lands: engine lane's problem per the brief). What this lane guarantees:
   when swing state lands, bars.lua renders it exactly (progress, texts, GCD
   underlay/markers, deadzone, class hooks unchanged — bars_state 907 green);
   when state is missing/empty, the bar shows the idle sliver + empty texts
   (the long-standing nil-guard path), and an unbuilt hand behaves exactly
   like a disabled bar (new guards). In-client proof needs the engine lane's
   START + the operator's copy.
2. Ranged bar shows the WRONG value on TBC (must show the hidden 0.5s Auto
   Shot window) — FIXED at the shared-state level. Two defects, both in the
   reader/cache layer the cast bar, the guide inputs and the Steady/Auto
   displays share:
   - a re-anchored cycle never cleared `ranged.hidden_window_start/duration`
     (the engine's START/UPDATE stamps next to the hunter sync's own clears;
     the reference clears on every StartSwing), so the previous cycle's
     window won over the live recompute;
   - an id-less live Auto Shot reading with a cold spell cache slipped past
     the `spell_id == 75 or name == ui.auto_shot_name` exclusion and rendered
     as a live "cast" instead of the window face.
3. Steady/Auto break when the ranged bar goes wrong — FIXED (same shared
   state): gather_guide_inputs and hunter_ui.get_hidden_window now accept a
   cached window only while `now` is inside it AND its end still lands on the
   live cycle's end (1e-9 epsilon for fp rounding); otherwise the cache is
   dropped and the live cycle recomputed. The engine additionally
   bounds-checks (is_in_window, inclusive) before any HOLD, so a future or
   past window can never hold.

## Files + lines (current tree)

- classes/hunter.lua: gather_guide_inputs provenance gate + recompute
  (recompute rides through verbatim; the engine bounds-checks), doc comment.
- hunter_ui.lua: read_live_cast fallback (`ui.auto_shot_name or "Auto Shot"`);
  get_hidden_window provenance gate + cache-only-when-inside (future
  recomputes, reference UI.lua:421-423).
- bars.lua: ST:bar_is_built + ST:ensure_bar (HU-22 gate: db.enabled AND
  (mainhand OR has_weapon), idempotent, never destroys); nil-safe getters;
  built-guards on 9 configure_*, onupdate_common, update_zones,
  on_bar_active/inactive, set_bar_texts, set_deadzone_width,
  set_gcd_marker_positions, set_gcd_width, set_bar_color. Zero behaviour
  change while init builds all hands (all suites green). Build points
  (init/equip/option-on in main.lua + option_tables) are the ENGINE lane's.
- tests/hunter_guide_state.lua: stale-cache pins re-cut to the provenance
  contract (outside-stale + inside-but-stale + current-cycle-hit), TBC +
  Forever HOLD ticks advance into the live window instead of injecting an
  off-cycle synthetic cache.
- tests/hunter_state.lua: id-less Auto Shot + cold cache keeps the window
  face (14d); re-anchor drops the cache, cast bar hides (new 14d2 block).

## Suite outputs (focused; full run.sh is the orchestrator's)

- bars_state 907 PASS; hunter_state 1744 PASS; hunter_window_state 213 PASS;
  hunter_guide_state 1970 PASS; hud_state 817 PASS; guide_contract 1052 PASS;
  shaman_state 1064, warrior_state 2046, paladin_state 1234, druid_state 1580,
  rogue_state 1114 (0 failures) PASS.
- luacheck on the 5 touched files: 0 warnings / 0 errors (floor holds).
- Ad-hoc bars exercise (/tmp/opencode/bars_check.lua, NOT committed — the
  committed ensure_bar suite + run.sh line belong to the queued lazy-bars
  lane): fixed tree 37 checks, 0 failures.

## Mutations (fresh /tmp/opencode copy per mutation, removed after)

- M1 gather provenance→inside-only: hunter_guide_state 4 FAIL, quoted
  (`an inside-but-stale cache loses... (got 99.7, want 101.45)` + clears).
- M2 read_live_cast fallback removed: hunter_state 2 FAIL
  (`keeps the window face (got Auto Shot 1.5, want Auto Shot 0.4)` + tint).
- M3 UI provenance removed: hunter_state 3 FAIL
  (`drops the previous window cache (got true, want false)` + clears).
- M4 ensure_bar gate removed: ad-hoc 2 FAIL
  (`enabled but no weapon builds nothing`, `gated-off hand stays unbuilt`).
- M5 onupdate_common guard removed: ad-hoc 1 FAIL
  (`unbuilt consumer runs clean (error: ...:698: attempt to index local 'frame'...)`).
- M6 blind get_anchor_frame: ad-hoc hard error
  (`bars.lua:491: attempt to index field '?' (a nil value)` at the bogus leg).
- All mutants reverted; copies removed. Fixed-tree suites re-ran green after.

## UNVERIFIED (evidence that would close each)

- U1 mainhand appears in-client (any class): needs engine START + operator
  copy; close with `/st diag` swing_mainhand counts climbing + visible bar.
- U2 TBC ranged 0.5s window in-client: needs operator copy; close with the
  cast bar showing "Auto Shot 0.x" in the window + Steady HOLD riding it.
- U3 engine ranged speed source on 2.5.6 (UnitRangedDamage returns damage
  not speed per the reference DEEP_AUDIT): lib/engine lane; close with
  in-client speed readings. If the engine speed is wrong, the window bounds
  derived from it are wrong too — display shows them truthfully regardless.
- U4 cast spark: no spark widget exists on the hunter cast bar in either
  addon (the reference moves a bar spark; Swedge swing bars have none) —
  filed as follow-up, not built (enhancement, not a wrong-value fix).
- U5 build points (init/equip/option-on calling ensure_bar) + committed
  lazy-bars suite + run.sh line: owned by the ENGINE lane / orchestrator.
