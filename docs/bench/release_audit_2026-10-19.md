# Release Readiness Audit — 2026-10-19 (live 2.1.1, report-only, zero code edits)

Scope: 7 TOCs + main.lua version, TOC module coverage/order, CHANGELOG [2.1.1] vs
landed work, smoke/wiring, stray files. Ledger (desks/journal.md) cross-checked vs tree.
Harness re-run in-lane to verify (read-only execution, no edits).

## Verdict: NOT READY — 5 PASS, 3 FILED (1 CHANGELOG gap is the release blocker)

### PASS

1. Version fields 2.1.1 (8/8) — PASS
   - SwedgeTimer.toc:5, SwedgeTimer_Vanilla.toc:5, SwedgeTimer_TBC.toc:5,
     SwedgeTimer_Wrath.toc:5, SwedgeTimer_Mainline.toc:5, SwedgeTimer_Cata.toc:5,
     SwedgeTimer_Mists.toc:5 → `## Version: "2.1.1"`; main.lua:5 → `local version = "2.1.1"`.
   - main.lua:6 `-- local version = "2.0"` comment kept by rule (version-bump brief).
2. Zero live 2.1.0 outside history — PASS
   - `grep -rn '2\.1\.0'` (excl. .git/docs): only CHANGELOG history is absent
     (no [2.1.0] header at all); remaining hits are intentional records —
     desks/journal.md:9,50,51, desks/release + desks/version-bump journals/signals,
     bench/briefs + buildout_release/buildout_version-bump, and one game-patch
     comment Libs/LibClassicDurations/diminishingReturns.lua:111 (game 2.1.0 DR, not addon).
3. TOC module coverage + dependency order — PASS
   - tests/toc_check.lua green: 788 checks, 0 failures (re-run in-lane).
   - Every root + classes/ .lua on disk listed in all 7 TOCs; compat.lua <
     swing_source.lua < main.lua, twist.lua < weave.lua < main.lua, shaman after main,
     rogue_guide in guide group, classes\rogue.lua after classes\warrior.lua —
     all pinned (toc_check.lua:196-228) and green.
   - LCTA divergence pinned both directions (toc_check.lua:254-270): ships only on
     Vanilla/TBC/Wrath; Mainline omits (stand-in/swing_source), Cata/Mists omit (nil tables).
   - Interface matrix: base advertises 11509,20506,38002,16001,120100,120105
     (SwedgeTimer.toc:1); Vanilla 11509 / TBC 20506 / Wrath 38002 exact;
     Mainline 120100,120105,16001; Cata 40402 / Mists 50500 parse as numbers;
     no toc advertises 30401. NOTE: Cata/Mists exact values are parse-checked only,
     not pinned exact (toc_check.lua:275-283 covers Vanilla/TBC/Wrath + contains for
     Mainline/base) — standing pattern, not a finding.
   - Newest modules pinned on every toc (toc_check.lua:319-327):
     diag.lua, hunter_window.lua, rogue_guide.lua, classes\rogue.lua.
4. Smoke / wiring green — PASS
   - bash tests/run.sh re-run in-lane: 38 steps, 0 failed (was 37 at reconcile;
     hud_templates_state is the +1). luacheck: 2 warnings / 0 errors in 76 files (floor).
   - tests/wiring_check.lua: 444 checks, 0 failures, 3 accepted known defects, 0 stale.
   - tests/toc_check.lua: 788/0 (see above). tests/smoke.lua unchanged scope.
5. No stray files — PASS
   - No *.bak / *.orig / *~ at root or depth-2 (excl. .git). No untracked root .lua
     outside TOCs (toc_check disk-completeness green). docs/swedge/* archived builds
     untouched per rule. bench/release_audit_* confirmed absent before writing this file.

### FILED (fix list for orchestrator / validation owner: orchestrator)

F1. CHANGELOG [2.1.1] does NOT cover landed work — RELEASE BLOCKER (docs accuracy).
    - CHANGELOG.md:3 `## [2.1.1]` ends at line ~256 (rogue post-section landings);
      no `Unreleased` header remains (grep zero) so all post-release-docs lanes
      (desks/journal.md rows 82–142, ~60 lanes) are unrecorded: rotation-fix wave ×6,
      followups wave ×5, templates-build, options-megapass, warrior-hamstring-slot,
      rogue-rupture-rows, shaman-searing-clock, paladin-hardwait, shaman-mana-sres,
      druid-ripcp-gather, options-ripcp, shaman-twistfeed, diag-ids-errors,
      hunter-multitarget FILED note, wrath-leftovers, sod-paladin-variants,
      druid-ffclaw, sod-variants-build, coe-m3-triage, warrior-bloodfrenzy 412507,
      hud-reconcile, hunter-tot-analytics, options-hooks, warrior-desync,
      bars-reconcile, icd-tracker, class-isolation, sim-defaults-options,
      practice-parity, hud-guide-verify, open-rules, hunter-open, wrath-sod,
      w2-hunter-badges, rogue-h6-sod, h2-cut, rogue-ema, druid-ttd-tick-reseal,
      shaman-icd, hud-templates-design, rogue-icons.
    - Spot-keyword grep on CHANGELOG.md: 412507/hamstring/rupture-rows/searing/
      hardwait/twistfeed/rip_min_cp/diag-ids/ffclaw/sod-variants/coe/h2-cut/
      desync/icd-tracker/sim-defaults/rotfix/followups/sod-detect/open-rules → all 0.
      Present: Steady-spam ×2 (early H2 text only), EMA ×4 (druid TTD only).
    - Fix: append late-lane entries under [2.1.1] (or cut [2.1.2]); owner: changelog lane.

F2. TESTING.md:33 diag example still `version=2.1.0` — stale doc, file for touch-up.
    - Version-bump lane scoped TOCs+main.lua only; the 2.0.8→2.1.0 pass had carried
      TESTING (desks/release/journal.md:9) but 2.1.0→2.1.1 did not.
    - README.md:61 `current: 2.1.1` is correct — PASS, no change needed there.

F3. desks/journal.md ledger stale rows — hygiene, orchestrator-owned.
    - Line 9 status: "Harness: 37 steps" (tree is 38 — hud_templates_state is the +1)
      and "CHANGELOG stays [Unreleased] until post-test publish" (release-docs flipped
      to [2.1.1], row 81). Reconcile/verify before in-client session.
    - Duplicate hunter-followups rows: row 62 `running` vs row 125 `done`, same session
      ses_eab601808ffe8BJ1jYayXwLA3o — close row 62 with pointer.

## Method (read-only)
Read all 7 TOCs + main.lua:5 + CHANGELOG.md (full) + tests/run.sh + tests/toc_check.lua
(full) + tests/smoke.lua + wiring_check.lua:1-60; `ls *.lua`, `classes/*.lua`, stray
glob; repo-wide `2.1.0`/`2.1.1` grep (excl. .git/docs); bench listing (release_audit
absent confirmed); executed `bash tests/run.sh`, `toc_check.lua`, `wiring_check.lua`
(execution only, zero edits). No git used. No class/guide/shared-system files touched.
