# shaman-family-scope — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Fix the release-gate blocker **B1**: the shaman's practice surface
  is not family-scoped. `ST.SHAMAN.practice_rotation` is a flat 22-row table
  whose per-row `families` field is dead data at runtime (token-validated by
  the suite only), there is no `practice_rotation_for` accessor, and
  `ST.SHAMAN.guide.slots` is a single static 22-slot list with no family
  filter — so a TBC client is offered rows the TBC APL does not carry (Call of
  the Elements, Molten Blast, Lava Lash, Chain Lightning, Windfury Totem,
  Grace of Air, Lightning Shield, Bloodlust). That violates `TESTING.md:175`
  ("A family that does not carry a row must never show it").
- **Scope:** `classes/shaman.lua`, `shaman_guide.lua`, `tests/shaman_state.lua`,
  `tests/shaman_guide_state.lua`. One new bench file. No git, no lint-config
  change, no TOC/version/option change, no other class touched, and
  `guide_contract.lua` / `practice_ui_state.lua` stay untouched (other lanes
  own them).
- **Build:** (1) a family-scoped accessor `ST.SHAMAN.practice_rotation_for(family)`
  (druid shape, `classes/druid.lua:3380-3395`) plus the running build's own
  token (the SoD game runs on the ERA client, so the SoD build names `SOD`);
  (2) family-scoped guide slots cut from the rotation table (the table's
  `families` is the one family truth); (3) pins: the per-family slice derived
  from the shipped table (exact action set + order), the accessor returning
  exactly that slice, and the strip-vocabulary pin (a TBC strip carries no
  WRATH-only and no ERA-only key); (4) the pre-pull table labelled honestly —
  `ST.SHAMAN.PRACTICE_PREPULLS` has NO consumer (only the warrior, hunter and
  rogue have a pre-pull drill).
- **Next step:** read the bench trail (done), implement the accessor + the
  family slot cut in `classes/shaman.lua`, pin them in the two shaman suites,
  prove the mutations on `/tmp/opencode` copies, and report the residual
  (the guide frame's own icon set stays the class's full vocabulary — the
  frame stacks one icon per slot and fades in only the current action's, so
  the narrower practice vocabulary changes nothing the player sees there).

## 2026-10-20 — The family scope landed
- **Worked on:** the blocker B1 fix in four files. `classes/shaman.lua` gained
  the family-scoped accessor (`practice_rotation_for` + `practice_rotation_family`
  + `practice_build_family` + `rotation_row_families`), the family guide-slot
  cut (`family_guide_slots`), the published-list narrowing
  (`apply_family_slots`, called from `post_init` after the guide frame and the
  HUD are built and before the practice surface is wired, plus the latch-driven
  re-cut in `refresh_weave_mw_stacks`), the class's full slot vocabulary
  (`ST.SHAMAN.GUIDE_SLOTS`) and the honest "NO CONSUMER" label on
  `ST.SHAMAN.PRACTICE_PREPULLS`. `shaman_guide.lua` needed **no** change — the
  family gate belongs to the class side, where the rotation table lives (one
  source of truth for the rows AND the slots). `tests/shaman_state.lua` gained
  the three audit pins (the derived per-family slice, the accessor returning
  exactly that slice, the TBC strip carrying no Wrath-only and no Era-only key)
  plus the per-family guide-slot pins, the SoD-build pins and the pre-pull
  "no consumer" source scan; `tests/shaman_guide_state.lua` gained the
  engine-side family-scope pins (the live answer names a slot in the client's
  set; every family gate that admits a row has that row in the set; the SoD
  build's set carries the Lightning Shield row).
- **Current state:** harness **41 steps, 0 failed**; luacheck **2 warnings / 0
  errors** (the floor). `shaman_state.lua` 834 checks, `shaman_guide_state.lua`
  1570 checks, `guide_contract.lua` 1052 (untouched), `practice_ui_state.lua`
  1623 (untouched). Nine mutants on `/tmp/opencode/mut_shaman_family` — **9/9
  killed**. `classes/shaman.lua` still at **199 file-scope locals** (no new
  file-scope local: every new function is a `ST.SHAMAN` field). Bench file:
  `bench/shaman_family_scope_2026-10-20.md`.
- **What did not work / was hard:** the guide frame's own icon set cannot be
  family-scoped without breaking `tests/guide_contract.lua`'s 22-slot pin
  (that file is another lane's, out of scope here) — the frame stacks one icon
  per slot and fades in only the current action's, so the family's cut changes
  nothing the player sees there; the narrowing therefore happens after the
  frame is built, in the practice-surface block, where the panel reads the
  list live. Mid-run the hunter suites went red from a **parallel hunter lane**
  editing `classes/hunter.lua` (11:52-11:57); those suites never load the
  shaman module and the final run on the settled tree is green.
- **Next step:** the orchestrator validates. Two residuals are filed in the
  bench file and need an operator ruling, not code: (1) the ERA token carries
  two games and the table's ERA rows are the token's truth, so an Era-base
  client is offered the SoD-only rows (splitting them needs a per-row build
  marker the table does not carry); (2) the Fire Elemental row is known-gated
  rather than family-gated in the gather, so the engine can still answer
  `fireele` on a client whose APL does not rank it (pre-existing).

## 2026-10-20 — [signal:done] the shaman's practice surface is family-scoped
- The blocker B1 fix is landed, pinned and mutation-proofed; the bench file
  carries the family truth table, the pin list, the mutant table and the
  residuals.
