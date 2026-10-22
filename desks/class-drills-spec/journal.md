# class-drills-spec — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Per-class completeness audit + practice spec. Two deliverables per class
  (six classes): (1) a rotation-feature checklist against the wowsims sim APLs, and
  (2) a target practice set = **one rotation SCENARIO** + **≥3 focused DRILLS**, each
  drill grading a different skill.
- **Scope:** READ-ONLY except ONE new bench file,
  `bench/class_features_drills_2026-10-19.md` (glob-verified ABSENT in-lane before
  writing). No addon/test/other-bench edits, no git, no edits to `practice.lua` /
  `practice_ui.lua` (a sibling lane owns them), no edits to class files.
- **Sources read (bench):** `class_matrix_2026-10-19.md` (feature matrix),
  `competitor_gaps_2026-10-19.md`, the six per-class rotation audits
  (`paladin_`, `warrior_`, `hunter_`, `rogue_`, `druid_`, `shaman_rotation_audit_2026-10-19.md`),
  `hunter_wa_map_2026-10-19.md`, `rogue_hunter_eratbc_2026-10-19.md`,
  `wrath_leftovers_2026-10-19.md`, `sod_paladin_variants_2026-10-19.md`,
  `rogue_rotation_gaps_closed_2026-10-19.md`, `practice_gamification_design_2026-10-19.md`,
  `buildout_practice_gamification_foundation_2026-10-19.md`,
  `shaman_drill_designer_2026-10-19.md`, `hunter_practice_designer_2026-10-19.md`,
  `paladin_practice_designer_2026-10-19.md`, `lessons.md`.
- **Desk journals read:** warrior-rotfix, shaman-rotation-fix, druid-rotfix,
  paladin-fixes, rogue-rotfix, hunter-rotfix (all 2026-10-19).
- **Next step:** write the bench file; then journal + signal.

## 2026-10-19 — Operator taxonomy landed mid-lane (two corrections)
- **Correction 1 (drill counting):** `rogue_energy_pool` counts as BASELINE resource
  behaviour, not a distinct drill skill. Effective real-drill counts:
  druid 1, hunter 1, paladin 2, shaman 1, warrior 1, rogue 1 (rogue energy is baseline,
  `rogue_ss_window` is the real one). Baseline resource behaviour does not count toward
  the target.
- **Correction 2 (taxonomy, changes the whole target):**
  - **SCENARIO** = running the class's actual wowsims rotation end-to-end. This is the
    primary practice mode for every class.
  - **DRILL** = a focused single-skill trainer (twist timing, weave fit, powershift,
    forced-move, execute phase).
  - Every current registry entry is a DRILL. **No class has a real SCENARIO yet.**
- **Target per class:** (1) one rotation SCENARIO driven from that class's sim APL
  (cooldowns, resources, priority order, transitions), grading the sequence the player
  actually casts; (2) ≥3 focused DRILLS, each grading a different skill
  (rotation priority order / cooldown-rotation-window usage / transition-opener /
  situational decision).
- **Design constraint:** prefer reusing each class's existing guide engine as the
  rotation driver (`st.nextaction.evaluate`, `st.warrior_guide.evaluate`,
  `st.hunter_guide.evaluate`, `st.rogue_guide.evaluate`, `st.druid_guide.evaluate`,
  `st.shaman_guide.evaluate`) so practice follows the same logic the guide teaches.
  Each scenario spec must state: rotation table source, tick model,
  expected-sequence comparison, grade bands.

## 2026-10-19 — Deliverable written
- **Worked on:** `bench/class_features_drills_2026-10-19.md` — new file, verified absent
  by glob before writing. Contents: §0 method/evidence bar, §1 taxonomy + counts,
  §2 the eight registry entries (all DRILLS) + the six per-class sections
  (paladin, warrior, hunter, rogue, druid, shaman), each with a feature checklist
  (WIRED / DEGRADED / MISSING with file:line + sim citation), the current drill
  inventory, the target drill specs, and the target rotation-SCENARIO spec; §3 the
  class parity tables; §4 the shared build-lane requirements; §5 the UNCONFIRMED
  ledger; §6 what was not compared; §7 validation owner.
- **Numbers:** every sim value carries its source citation; grading bands are labelled
  [DESIGN] (addon policy, not sim-sourced) so no band is mistaken for a sim number.
- **Anchor discipline (the part that needed the most work):** the per-class audits
  quote line numbers from the moment they were written, and several of those anchors
  have since drifted. Every `file:line` in the bench file was re-verified against the
  current tree, and where an audit row was stale it is marked as such rather than
  copied forward. Corrections made: the hunter Explosive downrank pair (60052/60053)
  HAS landed (`classes/hunter.lua:144-146`) — the audit's "53301 only" note is
  superseded; the shaman guide now ships **15** slots, not 13 (the G2 lane grew it),
  so the LS/CoE gap needs a 16th; the Retail short-circuit moved to
  `nextaction.lua:446`; the rogue tick constants moved to `classes/rogue.lua:94-96`;
  the druid clip helper is `druid_guide.lua:634` and `fight_is_young` is `:582-586`.
- **Current state:** bench file written (1241 lines); no other file touched; no git.
- **Next step:** orchestrator validates, then dispatches the build lane.

## 2026-10-19 — [signal:done] class feature + drill/scenario spec delivered
- `bench/class_features_drills_2026-10-19.md` — per-class feature checklist (6 classes,
  ~110 rows), drill inventory, 18 target drill specs + 6 rotation-SCENARIO specs, class
  parity table, build-lane requirements, UNCONFIRMED ledger.
- Headline finding: **no class has a rotation SCENARIO** (all eight registry entries are
  DRILLS), and **all six classes are missing the priority-order drill and the
  opener/transition drill**.
- Validation owner: orchestrator.

## 2026-10-19 — Anchor re-verification after parallel lanes moved two class files
- **Worked on:** re-ran every `classes/hunter.lua` and `classes/warrior.lua` anchor
  after those files were rewritten by other lanes mid-session (20:22 and 20:24). The
  drift was real: the hunter gather moved 1844 → 1963, the guide slots 2151 → 2276,
  the HUD row 2207 → 2333, the nil-written gather inputs 2126 → 2251-2254; the warrior
  gather moved 2764 → 2779, the guide 3063 → 3078, the HUD family sets 3143 → 3158,
  the OP/core-reserve/BT/WW constants 56/253/961 → 61/258/966, the execute feed
  1203 → 1208, the Sunder gather 2451 → 3045. All corrected in the bench file.
- **Current state:** bench file anchors verified against the tree **as of 20:30**.
  A reviewer must re-check the two class files before trusting their anchors — the
  parallel lanes are still moving them.
- **Next step:** orchestrator validates; if the build lane starts after another class
  file lands, re-grep the two anchors in §2.2 (warrior) and §2.3 (hunter) first.
