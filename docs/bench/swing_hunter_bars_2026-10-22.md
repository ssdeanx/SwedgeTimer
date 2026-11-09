# Swing hunter bars lane (2026-10-22): id-less live-cast Steady fix + mh no-change proof

Desk `swing-hunter-bars`. Write scope held: classes/hunter.lua only
(hunter_ui.lua, bars.lua, main.lua untouched). No run.sh/Libs/TOC/version/
option/other-class edits. HU-29 (lib untouched), HU-31 (classic line only).

## Symptom verdicts

### (1) Steady Shot dead while ranged is live — FIXED in classes/hunter.lua

Root cause: every live-cast Steady/Multi/Aimed/Sniper reader matched the
numeric spell id ONLY, but TBC payloads can ride name-carrying/id-less
(R1: `token = spell_id or cast_guid` in on_spellcast_event; compat.lua
"older classic payloads carry no numeric id"; operator binding rule
Anniversary = NAME). With an id-less live Steady:
- cast bar: still showed Steady (read_live_cast is name-sufficient — proved
  with P1b/P1c, TBC, id + id-less payloads),
- guide rule-1 arm, slot swipe pair, gather `steady_remaining`,
  H2 clip sampler: ALL blind (P2: `steady_remaining` nil, Era and TBC),
- SUCCEEDED/FAILED_QUIET queue-tint clears: missed (raw id lookup), leaving
  a stuck Steady/Raptor tint on name-carrying payloads.
So the cast bar and the guide disagreed: window face vs no prompt/swipe.

Fix (id primary, name secondary — behavior-neutral when ids present):
- new cached `shot_names_for` + `is_hunter_live_cast(id, spell_id, cast_name)`
  beside queue_tokens (tick paths must not spend a client query per id per
  frame; cold cache reads nil and retries, never a frozen empty set);
- gather's 4 live-cast arms (steady/multi/era-aimed/forever-sniper) through it;
- `is_hunter_shot_cast(spell_id, cast_name)` through it; track_live_cast key
  `(cast_spell_id or cast_name)` (old key errored on nil id);
- SUCCEEDED + FAILED_QUIET clears unified on the R1 matcher
  `is_hunter_queued_melee_token(spell_id or cast_guid, table)` (moved to the
  top: its callers precede the old site in source order; logic unchanged).

### (2) Hunter mainhand bar never shows — NO CODE CHANGE (proved correct)

End-to-end trace, Era + TBC separately (S2 probe legs on /tmp copies):
- mh built at init with tick installed (bars sandbox, both families);
- dispatcher START with the classic unit-id lead lands mh state and is
  counted (main sandbox, both families);
- visibility matrix with the shipped hunter keys (both + require_in_range):
  hidden at 30 yd, shown at 3 yd with a live cycle (both families).
The code is correct; only live melee swings are missing — a hunter at range
never melees, so MH never STARTs and the shipped keys hide it. Per the brief,
no change. In-client close-out (operator): go into melee — MH appears and
sweeps; /st diag `swing_mainhand` counts climb.

## Out-of-scope residual (orchestrator-owned)

C3: nextaction_ui.should_show + its mainhand-only on_bar_update tick gate
the whole hunter guide on melee swing state (nextaction_ui.lua:449-467,
:825-833). At range the guide frame cannot show by construction. No in-scope
fix exists that is not state-faking (mirroring ranged state into mainhand
corrupts the MH bar, its texts and LDB) — filed, not fixed.

## Files + lines (this lane)

- classes/hunter.lua only: matchers (~+70), 4 gather arms, sampler + key,
  2 clear-site unifications, matcher move (comment deltas only).

## Validation (focused — full run.sh is the orchestrator's)

- 25 suites green: hunter_state 1744, hunter_guide_state 1970,
  hunter_window_state 213, hud_state 817, guide_contract 1052, bars_state 935,
  bars_lazy_state 37, main_init_state 975, real_wire 882/0 (3 xfail HU-29),
  class_activation 70, neutral_actions 7026, options_load 3501,
  practice_ui 2529, prepull_contract 124, range_source 148, rogue 1114,
  rotationtext 244, warrior 2046, shaman 1064, paladin 1234, druid 1580,
  wiring_check 872, secret_guard 432, spell_known 251, lrc_guard 141.
- luacheck full tree: 2 warnings / 0 errors (pre-existing floor).
- Mutations (fresh full-tree /tmp copies, removed after):
  M1 tick-matcher name leg neutered -> P4 Era+TBC gather legs red (2 FAIL),
  all suites green (behavior-neutral for id shapes).
  M2 event-matcher name loop neutered -> P4c name-SUCCEEDED red (1 FAIL),
  all suites green.
- Fix legs (/tmp/opencode/probe_hunter.lua P4, Era+TBC separately): id-less
  Steady detected (steady_remaining 1.5), R1 name-SUCCEEDED clears the tint,
  Era id path unchanged. S2 legs (/tmp/opencode/probe_mh.lua,
  probe_mh_bars.lua): build + START + visibility matrix, Era+TBC.

## UNVERIFIED (in-client evidence that closes each)

- U1: id-less live payloads occur on the operator's TBC client (the fix is
  behavior-neutral if they never do; no in-client failure mode either way).
- U2: hunter melee test — MH appears/sweeps, diag swing_mainhand climbs.
- U3: C3 guide-frame gate needs an operator call (new lane with
  nextaction_ui scope, or accept melee-gated guide for hunters).

## Addendum (2026-10-22): legs committed to the shipped suites

- Owning suites: tests/hunter_guide_state.lua owns gather inputs (it pins
  every frozen input incl. the live-cast detection); tests/hunter_state.lua
  owns the class hooks (SUCCEEDED/FAILED_QUIET clears) and the H2 sampler.
- hunter_guide_state.lua (+6): id-less Era Steady gather (0.8/1.3),
  id-less TBC Steady gather (0.8/1.3), cold-cache unknown-hides leg.
- hunter_state.lua (+15): TBC name-carrying SUCCEEDED/FAILED_QUIET clears
  (7 incl. foreign-name no-op + recolour pins), Era+TBC id-less sampler legs
  (8). One leg hardened (`or {}` guard) so a red leg FAILs instead of
  aborting the suite.
- Green: hunter_state 1759, hunter_guide_state 1976, + window/hud/contract/
  bars spot suites; luacheck 0/0 on all three touched files.
- Mutations (fresh full-tree /tmp copies, removed after): M1 tick-matcher
  neutered -> 4 hunter_state + 4 guide FAILs, rest green; M2 event-matcher
  neutered -> 4 hunter_state FAILs, guide green (path separation holds).
