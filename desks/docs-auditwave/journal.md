# docs-auditwave — Journal

## 2026-10-20 — Desk opened
- **Purpose:** the final release-docs truth pass — make the documentation match the build that
  exists, including the six-defect **audit-fix wave** that landed after the last docs pass
  (the Phase-8 `docs-truth` pass of 2026-10-20 04:31 predates it).
- **Scope (exactly four files):** `CHANGELOG.md`, `TESTING.md`, `README.md`,
  `bench/live_test_script_2026-10-19.md` (extended **in place** — never a second script).
  No `.lua`, no test file, no other bench file, no TOC, no version, no git write.
- **Evidence bar:** every claim cites the bench artifact that carries it; every in-client item
  is marked UNCONFIRMED; no invented URLs, ids, numbers or in-client observations.
- **Next step:** read the plan (Phase 8) + the six newest bench artifacts, then write.

## 2026-10-20 — the audit-fix wave is documented (done)
- **Worked on:** exactly the four files above.
  - **CHANGELOG `[2.1.1]`** — a new section **"Audit-fix wave (2026-10-20, verified offline,
    UNCONFIRMED in-client)"** with all six findings, each carrying its bench citation: the two
    HIGH (the druid's press-nothing hold graded as an action; the session-end write that only
    fired on stop) and the four MEDIUM (the mid-session reset dropping later attempts; the
    paladin's family gate; the `is_spell_known` contract; the daily-cap freeze). Two
    **corrections to earlier passes**: (a) the "Scenario surface + APL utility layer" section
    still said the druid "states **none**" — that claim was the HIGH defect's origin and is
    superseded, with a pointer to the fix; (b) the same section's paladin bullet said the
    pre-pull table carries two rows — it carries **eleven** (and the rotation table **17**
    rows, the guide **twelve** slots, the HUD **fourteen**), now cited to the APL build, the
    HUD band and the audit close.
  - **TESTING.md** — four new checks: the **druid's press-nothing hold** (the bear's queued
    Maul: HOLD, no "ride" button, pressing nothing = no points, pressing anything = F); the
    **logout persistence** (log out → log in; run counter, time active, history row, daily
    streak — with the `/reload` caveat stated); the **mid-session reset** (no half-state); and
    the **paladin's practice strip per family** (TBC offers no "Hammer of Wrath"). The stale
    "the druid has no hold concept" line is corrected to the shipped split (one press-nothing
    hold, nine spell-naming holds). The existing surface list was re-verified against the
    tree and stays true (diag shape, six-class guides line, `providers=6/6`, drill counts
    3/6/4/4/4/4, the 13 design elements).
  - **README.md** — one correction: the pre-pull sentence claimed "the pre-pull drill grades
    the opening sequence" for every class. Verified in-tree: the **warrior, hunter and rogue**
    ship a pre-pull drill that grades the utility rows, the **paladin's** grades the pre-pull
    **seal**, and the **druid's and the shaman's** carry their pre-pull rows as citations
    only (tables, no drill). Rewritten to say exactly that. Nothing else in the README was
    false against the shipped build — checked line by line (drill counts, the six scenarios,
    the utility-layer list, the XP/level/mastery/streak progression, the Progress page, the
    18 templates + Custom, the local-only promise) and all hold.
  - **bench/live_test_script_2026-10-19.md** — extended in place: **§5.6** the druid's
    press-nothing hold; **§7.11** the logout-persistence check **and the reload caveat** (a
    UI `/reload` fires no `PLAYER_LOGOUT` and writes no SavedVariables — log out instead);
    **§7.12** the mid-session reset; **§1.9** the paladin's strip per family; the stale
    "the druid states no hold at all" line in §7.2 corrected; a **P10 rows** table (four
    still-UNCONFIRMED items) in §9; the report-back format in §10 extended with the
    audit-fix block; and a third extension note in the header so the script keeps describing
    the build that exists.
- **Current state:** harness **41 steps / 0 failed**; luacheck **2 warnings / 0 errors in 83
  files** (the standing floor — re-run after the doc edits; no `.lua` was touched). Line
  endings preserved (**CHANGELOG CRLF** — 838 CRLF lines + the file's original single
  no-newline last line; README / TESTING / the script LF, all 0 trailing-space lines in the
  lines I wrote). The CHANGELOG's 3 pre-existing trailing-space lines are untouched (same
  content, shifted down). The live script's cross-references all resolve (§1.9, §5.6, §7.11,
  §7.12, the P10 rows, the §10 report-back) and only **one** script exists — no second
  file was created.
- **One thing the earlier passes had wrong that no lane artifact flagged** (found by
  re-verifying the README's practice paragraph against the tree rather than against the
  bench): the README said "the pre-pull drill grades the opening sequence" for every
  class. In-tree: the **warrior, hunter and rogue** ship a pre-pull drill that grades the
  utility rows, the **paladin's** grades the pre-pull **seal** (`paladin_prepull` compares
  `up ~= spec.seal`), and the **druid and shaman ship no pre-pull drill at all** — their
  `PRACTICE_PREPULLS` tables are citations only. Corrected in the README.
- **Next step:** orchestrator validation. Two things it should check in-tree: (a) the new
  CHANGELOG section's numbers against the tree (the paladin's 17 rotation rows / 12 guide
  slots / 11 pre-pull rows / 14 HUD slots), and (b) that the druid's press-nothing hold is
  still a hold in the current tree — the parallel lanes were writing `classes/druid.lua` and
  `classes/rogue.lua` while this pass ran, so the shipped behaviour must be re-confirmed
  against the final tree before release.
- **Not done here (out of scope by dispatch):** the version decision (2.1.1 — the operator
  owns it) and any in-client confirmation. The central ledger row was added with the
  session id left as "— (orchestrator to fill)" rather than inventing one.

## 2026-10-20 — [signal:done] the audit-fix wave is documented
- The four release-docs files match the build that exists, including the six-defect
  audit-fix wave: CHANGELOG `[2.1.1]` carries the wave with a citation per finding (and
  two corrections to the earlier passes), TESTING.md carries the four new checks, README's
  one false pre-pull sentence is corrected, and the operator's live script is extended in
  place (§1.9, §5.6, §7.11, §7.12, the P10 rows and the reload caveat).
- Signal: `desks/docs-auditwave/.signals/2026-10-20T15-20-00Z.json` (execution/done,
  run id `docs-auditwave-2026-10-20`). Validation owner: **orchestrator**.
