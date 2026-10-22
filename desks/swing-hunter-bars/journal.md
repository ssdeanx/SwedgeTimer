# swing-hunter-bars — Journal

## 2026-10-22 — Desk opened
- **Purpose:** TBC hunter post-copy defects: (1) Steady Shot display dead while
  ranged is live (both must render simultaneously, all 4 combos), (2) hunter
  MH swing bar never shows.
- **Scope:** classes/hunter.lua, hunter_ui.lua, bars.lua hunter paths,
  main.lua hunter-relevant handler lines ONLY. No run.sh, vendored Libs,
  TOCs, versions, options, other classes. Era=ID / Anniversary=NAME legs
  separate; HU-29 (lib untouched); HU-31 scope.
- **Next step:** baseline touched suites, then sandbox probes reproducing both
  symptoms before any edit.

## 2026-10-22 — Diagnosis (probes on /tmp/opencode copies, tree untouched)
- **Worked on:** baselines (hunter_state 1744, hunter_guide_state 1970,
  bars_state 935 — all PASS); probe_hunter legs P1 (cast-bar matrix) + P2
  (gather live-cast matrix, Era+TBC) + P3 (TBC queue-token path); doc checks
  via git show (classic_era + classic_anniversary UnitDocumentation).
- **Current state:**
  - P1 (TBC, ranged live): window face OK; Steady WITH id hands over OK;
    Steady WITHOUT id hands over OK. Cast bar innocent for every payload.
  - P2: gather steady_remaining = 1.5 WITH id, nil WITHOUT id (Era and TBC).
    Guide rule-1, slot swipe, H2 sampler key on the id-only match: an
    id-less live Steady is invisible to all three while the cast bar shows
    it. R1 evidence (G1 matcher, spell_id-or-cast_guid token, compat
    "older classic payloads carry no numeric id") + operator NAME rule =
    fix with name-fallback matching, id primary (behavior-neutral).
  - C3 residual (out of scope): nextaction_ui.should_show + mh-only tick
    gate the hunter guide on melee state (nextaction_ui.lua:449-467,
    :825-833). Residual for orchestrator.
  - Symptom 2: MH build gate holds; at-range hide is BY DESIGN (pinned);
    no hunter-specific MH killer in main.lua/bars.lua. Main.lua sandbox
    legs still to run to prove code-correct-no-swings or find the break.
- **Next step:** name-fallback fix in classes/hunter.lua (gather 4 arms +
  is_hunter_shot_cast/track_live_cast + unify 4 queue-clear sites on the R1
  matcher), Era+TBC legs red-first, then symptom-2 main.lua legs.

## 2026-10-22 — Fix landed, lane done
- **Worked on:** E1 matchers (cached tick helper + G1 matcher moved to top),
  E2 gather 4 arms, E3 sampler/key, E4/E5 SUCCEEDED+FAILED_QUIET unification;
  luacheck 0/0 on the file; 25 suites green (list in
  bench/swing_hunter_bars_2026-10-22.md); M1/M2 red-first mutations on fresh
  full-tree /tmp copies (removed after); S2 proof legs (probe_mh,
  probe_mh_bars, Era+TBC) — mh path code-correct, no change per brief.
- **Current state:** (1) fixed — id-less live Steady/Multi/Aimed/Sniper now
  detected by guide + sampler + clears while the cast bar already showed
  them; (2) no change — built/ticking/START/visibility all prove out, only
  live melee swings missing. Residual C3 (guide frame mainhand gate,
  nextaction_ui.lua, out of scope) filed. Done signal filed.
- **Next step:** orchestrator: full run.sh, reconcile, operator copy +
  in-client U1 (id-less payloads occur), U2 (melee MH test), U3 (C3 call).

## [signal:done] lane complete
- Fix in classes/hunter.lua only; 25 suites green; luacheck floor holds;
  M1/M2 kill red; S2 proved code-correct with legs, unchanged.

## 2026-10-22 — Legs committed (continuation)
- **Worked on:** committed the P4 proof legs to the owning suites —
  tests/hunter_guide_state.lua (+6: Era/TBC id-less gather + cold-cache
  unknown-hides) and tests/hunter_state.lua (+15: TBC name SUCCEEDED/
  FAILED_QUIET clears + Era/TBC id-less sampler legs, one leg hardened with
  an `or {}` guard so red FAILs instead of aborting); no product changes,
  no run.sh.
- **Current state:** hunter_state 1759, hunter_guide_state 1976 green (+
  window/hud/contract/bars spot suites); luacheck 0/0 on all three touched
  files; M1 (tick matcher) red on 4+4 committed legs, M2 (event matcher)
  red on 4 committed legs, everything else green; full-tree copies removed.
  Bench addendum filed. Done signal filed.
- **Next step:** orchestrator: full run.sh, reconcile, commit (product +
  suite files together), operator copy + in-client U1/U2/U3.

## [signal:done] legs committed
- 21 committed legs (6 guide-state + 15 hunter-state), suites green,
  M1/M2 kill red on exactly the new legs; no product or run.sh changes.
