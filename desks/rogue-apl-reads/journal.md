# rogue-apl-reads — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Close the rogue's four filed residuals from the utility-layer lane
  (`bench/rogue_apl_utility_build_2026-10-20.md` §2 and the `live = false` rows):
  the Forever Vanish (the Garrote energy cost), the WotLK Hypersharp row, the
  Forever Gnome Eureka row and the TBC Backstab row — each either wired with an
  honest arm or flipped to a truthful flag state with the reason.
- **Scope:** `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua`,
  `tests/rogue_guide_state.lua`. No git, no lint-config change, no TOC/version/
  option change, no other class touched.
- **Input:** the rogue-apl desk's bench file (§5 and the four filed rows) plus a
  fresh re-fetch of the APL files and the sims' own spell data on 2026-10-20.
- **Next step:** write the reads and the arms, pin them in the rogue suites, prove
  the mutations on `/tmp/opencode` copies, land the bench file.

## 2026-10-20 — [signal:done] The four filed residuals are closed
- **Worked on:** re-fetched the four APL files (Forever, WotLK mutilate + combat,
  TBC swords) and the sims' own spell data (the generated client databases
  `wowsims/{wotlk,forever} assets/database`), then closed the four rows the
  utility layer filed: the **Forever Vanish** is WIRED (the Garrote's current
  energy cost — `api.GetSpellPowerCost` + the client's own
  `Enum.PowerType.Energy`, compared with the class's own energy pool), the
  **Forever Gnome Eureka!** is WIRED (the three readable disjuncts of the
  APL's own variable: the Adrenaline Rush's known-vs-on-cooldown split, its
  buff aura, and its time to ready against the racial's full cooldown), the
  **WotLK Hypersharp** row's filed reason and name are corrected and its dead
  arm removed, and the **TBC Backstab** stays honestly off (its gate is the
  APL's build CONSTANT, not a client-side state). The builder rows now say in
  their own notes that `engine = false` is a de-duplication, not a gap, and the
  class suite pins that.
- **Current state:** `tests/rogue_state.lua` PASS (939 checks),
  `tests/rogue_guide_state.lua` PASS (921 checks), the full harness 41 steps /
  0 failed, luacheck 2 warnings / 0 errors (the floor; the four touched files:
  0 warnings). Line endings held (the two addon files pure CRLF, the two test
  files pure LF), no trailing whitespace. 27/27 mutations killed on
  `/tmp/opencode` copies (`python3 /tmp/opencode/mutations_rogue_reads.py`).
  Artifact: `bench/rogue_apl_residual_reads_2026-10-20.md` (the utility
  layer's own file carries a pointer to it).
- **Decisions worth the trail:** the brief inherited the utility layer's filed
  premise — "the Hypersharp row is a permanent enchant". That premise is
  **refuted**: 54758 is "Hyperspeed Acceleration", the Engineering **belt
  enchant's effect** (the sim: a 60 s cooldown that applies a 12 s haste aura),
  and "Hypersharp Weapon" does not exist in the WotLK client at all. So the
  row's flags stay (`live = false`, `engine = false`) — the line still cannot
  be evaluated, because an item effect's availability has no read — but the
  reason is now exact, the name is the client's own, and the never-firing arm
  is gone (so `engine = false` is literally true). Two more name corrections
  landed with it: 1259812 is the Gnome **racial** "Eureka!", not "Gnome
  Eureka" (the APL's variable name). A **"db." in a class-file citation is a
  landmine**: the options suite scans `db.<key>` and every occurrence becomes a
  fake option key (it caught my own `assets/database/db.json` citation).
- **What this changes for the player:** the Forever client's guide can now
  prompt two more slot-less actions (Vanish, Eureka!) and the Forever practice
  panel's button row grows by two. Nothing else moves: the WotLK loses a rule
  slot that could never fire, and the Era/TBC clients are untouched.
- **Open items for the operator / the next lane:** the Gnome Eureka! row's
  fourth disjunct (the fight's remaining time) has no read — the row
  under-prompts rather than guess; the belt row needs the belt's item name for
  `api.GetItemCooldown` and the haste buff's aura id is UNCONFIRMED in-client;
  the two corrected names want in-client confirmation (the ids are citations —
  the class resolves spells by NAME); the TBC's builder divergence (the class
  may play Backstab on a dagger while the TBC APL's constant says otherwise) is
  unchanged and outside this lane's scope.
- **Next step:** the orchestrator validates. The next build lane is the one
  that gives the fight a remaining-time read (the fourth disjunct) and the
  belt's item cooldown, and a `practice_ui` row-height pass if the panel's
  button strip needs a cap.
