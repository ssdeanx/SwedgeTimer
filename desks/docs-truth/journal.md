# docs-truth — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Phase 8 of `bench/final_completion_plan_2026-10-19.md` — the documentation
  truth pass. Make the release documentation say what actually shipped, and correct the two
  bench files the plan names.
- **Scope (exactly four files):** `CHANGELOG.md`, `TESTING.md`, `README.md`,
  `bench/practice_gamification_design_2026-10-19.md`, `bench/live_test_script_2026-10-19.md`.
  No addon file, no test file, no other bench file, no git, no version/TOC change.
- **Evidence bar:** every claim cites the bench artifact that carries it; everything in-client
  is marked UNCONFIRMED; no invented numbers, ids, URLs or in-client observations.
- **Next step:** read the plan + the bench corpus, then write the CHANGELOG's `[2.1.1]`
  extension (rotation scenarios + drills, gamification, audit fixes, closure wave), the
  TESTING.md checklists, the README feature lines, the gamification-design §6 correction and
  the live-test-script extension.

## 2026-10-20 — Phase-8 documentation truth pass (done)
- **Worked on:** exactly the four files the dispatch named —
  `CHANGELOG.md`, `TESTING.md`, `README.md`,
  `bench/practice_gamification_design_2026-10-19.md`,
  `bench/live_test_script_2026-10-19.md`. No addon file, no test file, no other bench file,
  no git write, no version/TOC change. Verified: `find . -name "*.lua" -newermt
  "2026-10-20 03:00"` returns **nothing** — no Lua was touched this session.
- **CHANGELOG `[2.1.1]` extended with four new sections** (the section header stays
  `[2.1.1]`; the operator owns the version decision):
  *Rotation scenarios + per-class drills* — the shared rotation-run engine, the practice
  mode select, all six classes' rotation scenarios, the 23 per-class drills (named per
  class), and the three superseded built-in drills; *Practice gamification* — XP/levels/
  renown, per-drill mastery + tiers, the three streaks, the seven achievements, the unlock
  registry (with the honest note that the cosmetic/drill-variant catalogues are empty),
  the stats, the Progress page, the stats frame + sparkline, the panel level badge, the
  persistence/repair contract, and the local-only (no export) correction; *Audit fixes* —
  F1 error-ring install, F2 offhand handler, F3 printer, F5 HUD counter, F7/F11 dead
  helpers, F4 name-vs-id with the absent-vs-unresolved latch, F6 base-TOC change, F10 the
  one shared guard, the `SCENARIO_RESOURCE_KEYS` crash, the HU-7 class-module namespace
  fix; *Closure wave* — the Wolfshead probe, the Serpent target scan, the CoE live slot +
  the per-family Stormstrike, the Flame Shock sim-exact default, the Hemorrhage builder +
  the swapped-id corpus fix, the Forever Echo/Holy Strike ids, and an explicit
  "**Not in this build**" line for the warrior HS/Cleave queue drill.
  Also corrected the older `[2.1.1]` line that still said "the four new guides ship
  disabled until verified in client" — all six guides now ship enabled
  (`nextaction_enabled = true` in every class default).
- **TESTING.md:** the `/st diag` sample now shows the six-class guides line and
  `providers=6/6` (it was a stale five-class `5/5`); the practice checklist grew the
  per-class drill sets, the practice-mode select, the rotation scenario, the Progress page,
  the stats frame + sparkline and the panel level badge; the design checklist names the
  current 13 elements (seal icons, Successful twist text, the two report frames) and says
  the level badge is **not** one of the 13; the "four guides default OFF" claim is gone
  from both the purpose paragraph and the "what NOT to conclude" list.
- **README.md:** the class table's drill column now lists each class's own drills; new
  lines for the rotation scenarios, the practice modes, the XP/level/renown/mastery/
  streak progression, the Progress page + sparkline, and the templates gallery (3 curated
  templates per class = 18 + Custom); the "newer guides ship OFF" line is replaced; the
  Links section now says plainly that the addon integrates with none of the listed project
  pages. Screenshots-pending, the class colour table, the practice explainer and the
  HUD/designer section are all kept.
- **Bench corrections (the two named files):**
  `practice_gamification_design_2026-10-19.md` — §0 rule 3, §5, §6's export bullet, §7
  step 5 and §9 rewritten: **this build ships no import/export surface** (no
  `import_export.lua` in the shipped addon; the only two in the repo belong to the
  *archived* addons under `docs/swedge/`), so progress is **local-only**; §5 now carries
  all three operator decisions (cosmetics + level-gated harder drill variants, the static
  achievement set, the no-punishment streak); §9 marks 1-3 **RESOLVED** and re-files 4-5
  as settled-by-default rather than open. The risk-register row was aligned with the
  operator's rewards ruling.
  `live_test_script_2026-10-19.md` — **new §7** (practice: the mode select, the rotation
  scenario per class, every class's drill list, the badge + XP bar, the Progress page, the
  stats frame + sparkline, the 13 design elements); **three stale class rows corrected**
  (§3.5 CoE "expect NOTHING" → the slot now exists on Wrath; §4.2 Serpent "upkeep
  MISSING" → the target read landed; §5.3 Wolfshead → the probe landed) and a new §1.8 for
  the paladin's Forever ids; **six new P8 rows** in the ID table (66842 + the water-totem
  read on 3.80.2, the Wolfshead read, the Serpent target read, the three Forever ids, the
  Slam cast-time read on a name-only TBC client, and the warrior HS-queue drill — recorded
  as **NOT SHIPPED**); the old §7/§8/§9 renumbered to §8/§9/§10 with the cross-references
  updated, and the trailing harness state refreshed to 41/0.
- **Current state:** the tree is **41 steps / 0 failed**, luacheck **2 warnings / 0 errors
  in 83 files** (re-run after the doc edits to confirm nothing moved: still 41/0, luacheck
  2/0 — no `.lua` was touched). Line endings preserved (CHANGELOG CRLF, the other four
  LF); zero trailing-whitespace lines in all five files.
- **Next step:** the orchestrator validates the five files in-tree. Two things the operator
  should know: (a) the **warrior HS/Cleave queue drill (plan Phase 2) never landed** — the
  desk `desks/warrior-hs-queue/` holds only an empty `.signals/` and there is no
  `warrior_hs_queue` drill in the tree, so it is documented as absent rather than shipped;
  (b) the CHANGELOG's `[2.1.1]` section now spans the whole wave, and the version bump
  (2.2.0) is still the operator's call.
- **Validation owner:** orchestrator.

## 2026-10-20 — [signal:done] Phase-8 documentation truth pass
- Five files only (`CHANGELOG.md`, `TESTING.md`, `README.md` + the two named bench files);
  no `.lua` touched, no git write, no version/TOC change. Signal:
  `desks/docs-truth/.signals/2026-10-20T043500Z.json`. The tree is 41/0, luacheck 2/0.
- Operator note: the **warrior HS/Cleave queue drill (plan Phase 2) never landed** — it is
  documented as absent in both the CHANGELOG and the P8 row of the live script, not as
  shipped. The version bump remains the operator's call.

## 2026-10-20 — Second documentation truth pass (the APL utility wave)
- **Worked on:** the four files the dispatch named — `CHANGELOG.md`, `TESTING.md`,
  `README.md` and the operator's live script. **No `.lua` touched** (verified: the only
  file newer than my first edit is `nextaction.lua`, written by a parallel lane at
  04:26 while I was editing the script), no other bench file, no TOC, no version, no git.
- **The tree moved on after the first pass.** The Phase-8 note "the warrior HS/Cleave
  queue drill never landed" is now **wrong** — it landed on 2026-10-20
  (`bench/warrior_hs_queue_2026-10-20.md`). The stale "Not in this build" bullet is
  **deleted** from the CHANGELOG and the P8-6 row of the script is corrected.
- **CHANGELOG** — one new dated section under `[2.1.1]` (the version bump stays the
  operator's call): the scenario-surface fixes (the paladin's F1 context builder, the
  shared F2 pick channel, the shaman/druid session routing, the frame leak, the Retail
  gate, the drill-counter keying, the twist drill's ownership), the HU-8 hold contract,
  the APL utility layer per class with the two-flag convention and the per-class pre-pull
  tables, the HS/Cleave queue drill with the sim's citation, the 31 corrected ids and the
  Forever druid Mangle removal. The "23 per-class drills" bullet was corrected to **25**
  (three to six per class) — the warrior gained `warrior_hs_queue` and `warrior_prepull`.
- **README** — the class table's drill column now matches the tree (warrior six, the
  paladin's list leads with the twist timing drill), "three or four" → "three to six", and
  a new paragraph states that the rotation scenario carries the **full** sim priority list
  (the utility layer), that the pre-pull rows live in a per-class pre-pull table, and that
  the scenario needs a live swing engine.
- **TESTING.md** — new checks for the utility rows, the hold contract, the pick channel, the
  class-session routing, the scenario row's hygiene, the HS/Cleave queue drill, the pre-pull
  phase and the Retail refusal; a new **"Still UNCONFIRMED in the 2026-10-20 wave"** list
  (seven items); the per-class drill sets and the practice-mode note counts corrected.
- **Operator script** — `bench/live_test_script_2026-10-19.md` was **extended in place**;
  no second script was created (the dispatch's own rule: never leave two). §7.2 gained the
  utility rows + the hold contract + the row's hygiene, §7.3 the pick channel + the session
  routing + the twist ownership, §7.9 the pre-pull phase and §7.10 the queue drill; the
  P8-6 row is corrected and **P9 rows** (seven still-UNCONFIRMED items) plus a
  **corrected-id table** were added to §9.
- **Current state:** harness **41 steps, 0 failed**; luacheck **2 warnings / 0 errors in 83
  files** (re-run after the doc edits to confirm nothing moved — no `.lua` was touched).
  Line endings preserved (CHANGELOG CRLF 721/721, README LF, TESTING LF, the script LF);
  zero trailing-whitespace lines in all four files.
- **Next step:** the orchestrator validates the four files in-tree. Two notes for the
  operator: (a) the **CHANGELOG's `[2.1.1]` section now spans two documentation passes and
  the APL utility wave** — the version bump (2.2.0) is still the operator's call; (b) the
  **operator script kept its 2026-10-19 date** because extending it in place was the only
  option the dispatch allowed ("never leave two scripts") — the header carries both
  extension notes so the reader knows it describes the current build.
- **Crossfire to flag (not a blocker):** while this pass ran, a **parallel lane was editing
  the paladin's rotation table** (`classes/paladin.lua` 04:29, `nextaction.lua` 04:26,
  `tests/paladin_state.lua` 04:29, `tests/guide_contract.lua`, `tests/nextaction_state.lua`)
  and had not yet written its bench artifact. The paladin paragraph in the CHANGELOG and
  the paladin bullet in the script §7.2 are therefore worded **non-exhaustively** ("the
  WotLK APL's two missing rows ride the rotation table"; "and any further APL row the
  build's paladin table carries"), so they stay true when that lane lands. **The
  orchestrator should re-read the paladin paragraph once that lane's bench artifact
  exists** and add the rows it brings. The other five classes' row lists come from landed
  artifacts and are complete.

## 2026-10-20 — [signal:done] Second documentation truth pass (APL utility wave)
- Four files only (`CHANGELOG.md`, `TESTING.md`, `README.md`,
  `bench/live_test_script_2026-10-19.md`); no `.lua` touched, no other bench file, no TOC,
  no version, no git. Signal:
  `desks/docs-truth/.signals/2026-10-20T090000Z.json`. Tree re-verified at 41/0,
  luacheck 2/0 in 83 files. The stale "not in this build" line about the warrior HS/Cleave
  queue drill is gone; the drill is documented as shipped.
