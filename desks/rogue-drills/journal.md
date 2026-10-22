# rogue-drills — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Rogue rotation SCENARIO + the audited target DRILL set (finisher order,
  combo-point decision, SnD upkeep, opener) + the rogue class-side feature gaps that
  §2(A) of the spec lists as MISSING/DEGRADED.
- **Scope:** `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua`,
  `tests/rogue_guide_state.lua` (the rogue guide test file EXISTS — glob-verified).
  No other file: `practice.lua` / `practice_ui.lua` / `option_tables.lua` /
  `config_presets.lua` / `config.lua` / other classes / `main.lua` / `diag.lua` /
  `compat.lua` / `hud.lua` / `bars.lua` / `run.sh` / TOCs / versions / README /
  CHANGELOG / docs are owned by sibling lanes. No git. No lint-config changes.
- **Spec:** `bench/class_features_drills_2026-10-19.md` §2.4 (rogue A/B/C/D).
  The shared engine looks the class side up by `player_class` — the fixed contract:
  1. `ST.ROGUE.practice_rotation` — rotation table in sim priority order, each entry
     citing its sim source.
  2. `ST.ROGUE.practice_scenario_step(self, ctx)` — `{ action, reason }` or nil
     (undecidable); ctx = `{ now, last_action, resources, cooldowns }`; reuses
     `st.rogue_guide.evaluate`.
  3. `ST.ROGUE.practice_drills` — `{ key, label, grade(self, ctx) }`; the audit's
     target drill set (C). Energy behaviour is BASELINE (operator ruling):
     `rogue_energy_pool` is NOT one of the target drills.
- **Next step:** read the rogue guide engine + provider, then implement the three
  contract entry points, pin them, close the class-side gaps that need no new
  external data, and file the rest with reasons.

## 2026-10-19 — Contract built, feature gap closed, evidence filed
- **Worked on:** the rogue rotation scenario + the audit's four target drills
  (`bench/class_features_drills_2026-10-19.md` §2.4 C/D) and the class-side feature
  gaps of §2(A).
- **Shipped:**
  - `classes/rogue.lua` — `ST.ROGUE.practice_rotation` (12 entries, the engine's rule
    order, every entry with `action`/`label`/`rule`/`note`/`source` + the family set),
    `practice_rotation_for(family)` / `practice_rotation_family()` (the engine's
    rotation-slice readers; RETAIL gets an empty slice), `practice_context(self, now,
    last_action)` (the class's own ctx builder, so the drills see the whole gathered
    state), `practice_scenario_step(self, ctx)` (a thin wrapper over the pure
    `st.rogue_guide.practice_step`), `practice_drills` (the four audit drills, each
    with `key`/`label`/`kind`/`description`/`grade`), and the `st.ROGUE = ST.ROGUE`
    namespace mirror (hands-up HU-7).
  - `rogue_guide.lua` — the pure practice surface: `build_practice_inputs`,
    `practice_expected`, `practice_reason`, `practice_step`, `get_practice_pick`
    (the ctx's aliases), `snd_duration_for_cp`, `family_floors`, `opener_rank`, the
    prepull/GCD constants and the four pure graders.
  - `classes/rogue.lua` + `rogue_guide.lua` — **R-19 closed in part**: the Wrath
    Hunger for Blood upkeep (rule 1c, `hfb_verdict`, the provider's name-resolved
    gather, the rotation label's fallback name). Sim source fetched live
    (wowsims/wotlk `mutilate.apl.json`: auraRemainingTime(51662) <= 1s -> cast).
  - `tests/rogue_state.lua` (+85 checks) and `tests/rogue_guide_state.lua` (+108).
- **The one thing that cost the most:** my FIRST pass defined the rotation entries
  with `sim`/`reason` and answered the POOL verdict with `action = "pool"`. Both are
  wrong against the SHIPPED engine (the sibling lanes' shaman/druid/paladin class
  sides and practice.lua's `H.practice_class_module` / practice_ui's rotation-slice
  reader had already landed). Read the CONSUMER before defining the PRODUCER's
  shape: the engine reads `entry.label`, `practice_rotation_for`,
  `practice_rotation_family`, `practice_context` and requires a non-empty
  `result.action` string. The table is now the house shape (`source` for the
  citation), and a POOL hold answers nil (see the hands-up signal).
- **Correction found in the spec:** the audit's §2(A) R-19/R-20 quote ids that do not
  survive a live look at the wowsims wotlk APLs — "Killing Spree (51690)" is 54758,
  and "Cut to the Chase 57934" is Tricks (57934 casts Tricks at energy <= 50). No id
  reaches our tables (every spell resolves by name), so it is a documentation fix.
  Also: three §2(A) rows were STALE (R-01's "no slot exists", R-09's Forever lockout,
  R-12/R-18's SoD reachability) — the tree closed them in earlier lanes.
- **Validation:** `tests/rogue_state.lua` 787/0 (incl. the end-to-end seam: the shared
  harness finds the rogue's drills + scenario step by `player_class` and drives
  both), `tests/rogue_guide_state.lua` 756/0,
  `bash tests/run.sh` **41 steps / 0 failed**, `luacheck .` **2 warnings / 0 errors**
  (the floor; both warnings are in compat.lua/main.lua, not in this lane's files).
  **20/20 mutations killed** on `/tmp/opencode/rogue-mut` copies (script
  `/tmp/opencode/rogue_mutations.sh`).
- **Four defects I found in my own first pass (and fixed + pinned):** the cooldown
  pass wiped the readiness flag the state bag had proved; the combo-point drill
  graded an unknown state "C" instead of nil; the opener's prepull read looked for a
  NUMBER where the readiness flag is a BOOLEAN; and the rotation slice had put Shiv
  on Era only (the engine's SHIV_FAMILIES is ERA + TBC). All four now have pins and
  their own mutations (M18-M20 + the slice pin).
- **Artifact:** `bench/rogue_drills_rotation_2026-10-19.md` — the contract, the ctx
  contract, the per-row §2(A) disposition, the citation corrections, the filed
  follow-ups (7) and the validation.
- **Current state:** the rogue side of the practice contract is complete and pinned;
  the shared engine registers the drills (sibling lane).
- **Next step:** the operator rules on the hands-up (the POOL/illegal-cast gap: the
  engine cannot express "expected = hold"); the sibling lane may want the
  `ctx.resources` upkeep state (the class publishes `practice_context` for it).

## 2026-10-19 — [signal:done] rogue rotation scenario + target drill set + R-19 closed in part
- `bench/rogue_drills_rotation_2026-10-19.md`; `ST.ROGUE.practice_rotation`,
  `ST.ROGUE.practice_scenario_step`, `ST.ROGUE.practice_drills` (four drills),
  plus the Wrath Hunger for Blood upkeep (rule 1c).
- 787 + 756 checks green (incl. the end-to-end seam through the shared harness),
  41/41 harness steps, luacheck floor held, 20/20 mutations.
- Validation owner: orchestrator.

## 2026-10-19 — [signal:hands-up] the POOL verdict cannot be an "illegal cast" in the shipped engine
- The audit's S-R wants a cast during a POOL verdict to be an illegal cast; the
  engine's `H.rotation_run_decide` compares two action strings (a nil expected reads
  as UNKNOWN, a mismatch reads as out_of_order/F), and there is no "pool" button in
  the panel - so a "pool" action key would make every POOL step an automatic F.
- All three landed class lanes answer a hold with nil. Operator ruling needed:
  the engine grows a hold verdict, or the audit's rule is amended.
- Signal: `desks/rogue-drills/.signals/20261019T214200Z.json`; the orchestrator owns
  the `hands-up.md` row (this lane did not edit that file).
