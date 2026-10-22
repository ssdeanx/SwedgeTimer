# druid-apl — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Build the druid's missing APL rotation lines (the utility layer: the
  Cat Form upkeep, the Leader of the Pack, the Feral Faerie Fire upkeep, the Claw
  builder, the Innervate, the Elune's Light, the Bloodlust) into
  `ST.DRUID.practice_rotation` with the APL priority citations, the per-family spell
  id + name, the family gates and HU-13's two flags (`live` = the read exists,
  `engine` = the frozen engine has an arm) - and give the frozen guide engine an arm
  for every line that can be armed honestly.
- **Scope:** `classes/druid.lua`, `druid_guide.lua`, `tests/druid_state.lua`,
  `tests/druid_guide_state.lua`. One new bench file
  (`bench/druid_apl_utility_build_2026-10-20.md`). No git, no lint-config change, no
  TOC / version / option / config change, no other class touched.
- **Source of truth:** `bench/rotation_gap_vs_apl_2026-10-20.md` §4 (the druid),
  re-verified against the fetched APL files (`wowsims/{classic,sod,tbc-new,forever,
  wotlk}` master) and the sims' own spell data plus the Classic 1.15 client's own
  tables (wow.export).
- **Next step:** read the gap file's druid section + the shipped rotation table,
  re-verify every id/index against the APL JSON, write the table, wire the engine
  arms, pin them in the druid suites, prove the mutations on `/tmp/opencode` copies.

## 2026-10-20 — The utility spine landed
- **Worked on:** re-fetched all five druid APL files and expanded every group inline,
  so the priority indices and the pre-pull offsets came from the files, not from the
  gap analysis; named every id against the sims' own spell data
  (`spell_data_auto_gen.go`, the per-ability `.go` files) and the Classic 1.15
  client's own tables. Wrote the rotation table's spine rows (Cat Form, the Leader
  of the Pack, the Feral Faerie Fire upkeep, the Claw builder, the Innervate, the
  Elune's Light, the Bloodlust), gave every shipped sim row its per-family `ids`
  and both flags, added the pre-pull table (HU-12), and gave the frozen engine four
  arms (the Faerie Fire upkeep on Era + TBC, the Leader of the Pack on Era, the
  Innervate on Era/SoD/Forever, the Elune's Light on Forever) - every one of them a
  HOLD, no new guide slot.
- **Current state:** `tests/druid_state.lua` PASS (1190 checks),
  `tests/druid_guide_state.lua` PASS (95582 checks), luacheck on the four touched
  files 0/0. The full harness is **41 steps / 0 failed** and the tree's luacheck
  floor is **2 warnings / 0 errors** (both pre-existing, in untouched files).
  21/21 mutations killed on `/tmp/opencode` copies (`python3
  /tmp/opencode/druid-apl/mutations_druid_apl.py` reproduces them). Artifact:
  `bench/druid_apl_utility_build_2026-10-20.md`. Verified **offline** only - no
  client run happened here.
- **Decisions worth the trail:** the druid needs BOTH flags and they come apart:
  four lines have a read and an arm (the Feral Faerie Fire upkeep, the Leader of the
  Pack, the Innervate, the Elune's Light), three have a read but no honest arm
  (Cat Form - the guide has no feral-spec gate, so an arm would nag every caster
  druid; the Bloodlust - the APL's own "Bloodlust Time" variable has no addon
  counterpart; the Claw - the read that decides "the Shred cannot land" does not
  exist, `can_shred` is RESERVED), and none of them ever guesses: every arm hides on
  an unreadable input.
- **Next step:** the operator's call on the filed items - the Forever Mangle defect
  (the shipped F5 row and the engine's FOREVER F5 rule name a spell the Forever
  client does not have, so the Forever chain's F6/F7 branches are unreachable
  there) and the Cat Form spec gate. Both are behaviour changes to shipped chains
  and were left out of this lane on purpose.

## 2026-10-20 — [signal:done] the utility spine landed
- The druid's APL utility layer is in `ST.DRUID.practice_rotation` (seven spine
  rows with the per-family ids, the APL citations, HU-13's two flags and the filed
  needs), the pre-pull table is in `ST.DRUID.PRACTICE_PREPULLS` (HU-12), and the
  frozen engine has four arms (the Feral Faerie Fire upkeep, the Leader of the
  Pack, the Innervate, the Elune's Light). Artifact:
  `bench/druid_apl_utility_build_2026-10-20.md`.
- Validation: `tests/druid_state.lua` PASS (1190 checks),
  `tests/druid_guide_state.lua` PASS (95582 checks), luacheck 0/0 on the four
  touched files, 21/21 mutations killed on `/tmp/opencode` copies, and the full
  harness **41 steps / 0 failed** (the tree's luacheck floor: 2 warnings / 0
  errors).

## 2026-10-20 — [signal:hands-up] HU-14: the FOREVER chain prompts a spell the client does not have
- The Forever client has no Mangle spell (no spell table, no per-ability file, no
  mention in the sim's feral files; the Forever APL's own builders are 9830 Shred
  and 9850 Claw). The shipped F5 row's citation named `mangleNow`, a function the
  Forever repo does not have - corrected in place, and the row now carries no id
  for that family.
- What is left is the engine's FOREVER F5 rule (`mangle_remaining nil -> mangle`):
  on the Forever client `mangle_remaining` is always nil, so the chain always
  answers "mangle" and the F6/F7 branches are unreachable. The fix is a behaviour
  change to a shipped guide and depends on the Claw line's read, which does not
  exist yet (`can_shred` is RESERVED; `api.IsSpellUsable`'s energy-cost semantics
  on the classic clients are in-client UNCONFIRMED). Raised as **HU-14** for the
  operator; NOT fixed here on purpose.

## 2026-10-20 — the filed residuals closed (HU-14, the dead APL rows, the honest flags)
- **Worked on:** the dispatch put this desk back on its own filed residuals. HU-14
  is closed: the FOREVER client has **no Mangle spell at all** (re-verified from the
  Forever sim's spell data, the Forever APL's builders — 9830 Shred / 9850 Claw — and
  the APL's empty slot there), so the engine's F5 Mangle branch is **removed** (the
  Bite and the builder are reachable again) and the table's FOREVER Mangle row is
  removed with it. The **same defect on the same client** — the bear chain's rule 3
  fallback — now waits there too (a named `druid_client_has_mangle` helper, the
  runeless-Era precedent). The two dead APL rows are reconciled and pinned: the Era
  APL's i=1 row casts 13494 = "Haste" (the 1.15 client's own name, confirmed on
  warcraftdb) and the line it means is the client's Leader of the Pack 17007; the
  Era APL has **no Rip row** and the table's E1 row says so and carries the client's
  Rip r6. The **Cat Form** row now has an arm: the gate the lane said was missing
  exists — the class's own Feral-tree spec probe (`api.is_spell_known` on the
  family's Feral-tree talent: the Faerie Fire (Feral) 17392 on Era/SoD, 27011 on
  TBC, the Leader of the Pack 17007 on Forever) plus the player's Cat Form aura
  (768, the class's own aura walk) plus the form state (the humanoid/travel form
  only), ordered against the Innervate row per family exactly as the APLs order
  them. The **Bloodlust** row is `live = false, engine = false` with the real
  reason: 2825 is the **Shaman's** Bloodlust (the TBC druid sim registers no
  Bloodlust, and the APL runner drops a row whose spell the actor lacks), so the
  line cannot be evaluated at all, and the APL's "Bloodlust Time" variable has no
  addon counterpart. The **Claw** stays RESERVED with both flags false.
- **Current state:** `tests/druid_state.lua` PASS (1205 checks),
  `tests/druid_guide_state.lua` PASS (95910 checks), luacheck 0/0 on the four
  touched files (the tree floor 2 warnings / 0 errors, untouched), **15/15
  mutations killed** on `/tmp/opencode` copies
  (`python3 /tmp/opencode/druid-residuals/mutations_druid_residuals.py` — including
  the required "a wrong action on a client without the spell" mutant), and the full
  harness **41 steps / 0 failed**. Artifact:
  `bench/druid_apl_residuals_2026-10-20.md`. **Verified offline** — no client run
  happened here.
- **Decisions worth the trail:** (1) the APL's slot where the FOREVER Mangle row
  stood is **empty**, so the honest fix is to delete the branch, not to invent a
  substitute — the chain then runs the APL's own order (Bleeds → Bite → Builders).
  (2) The bear fallback was the same defect on the same client; it is closed with
  the same rule even though HU-14 only named the cat chain (stated in the bench
  file). (3) The Cat Form gate is a **spec proof**, not a setting: the Feral-tree
  talent probe excludes a resto/balance druid, and the KNOWN LIMIT (a Feral-tree
  bear tank out of the bear form can still be told to shift — the clients expose
  no cat-vs-bear talent read outside WotLK) is written into the row's `gate`
  text, not hidden. (4) `live` now means "the read exists **and the line can be
  evaluated from it**" (the bench's own definition), so the Bloodlust row is
  `live = false` — the cooldown probe exists but reads a spell the druid cannot
  cast. (5) The arm adds one HOLD to the guide's own surface (the guide ships
  enabled), so a Feral-tree druid proven out of the cat form now sees the APL's own
  row; no options widget was added (`option_tables.lua` is out of scope).
- **Next step:** the operator's reconcile on the three filed follow-ups (the SoD
  Mangle-rune case — the same defect class on a family HU-14 does not cover; the
  cat-vs-bear spec read; the Bloodlust option). The lane's own lane row in
  `desks/journal.md` is the orchestrator's to write (no session id was handed to
  this desk).

## 2026-10-20 — [signal:done] HU-14 closed, the dead APL rows reconciled, the flags honest
- HU-14 is closed: the engine's FOREVER F5 Mangle branch and the rotation table's
  FOREVER Mangle row are gone (the client has no Mangle spell; the APL's slot there
  is empty), so the Bite and the builder are reachable again; the bear chain's
  fallback waits on that client too. The Era APL's dead 13494 ("Haste") row and the
  Era APL's missing Rip row are reconciled and pinned. The Cat Form row has an arm
  behind the Feral-tree spec probe + the Cat Form aura + the form state; the
  Bloodlust row is `live = false, engine = false` (2825 is the Shaman's spell); the
  Claw stays RESERVED with both flags false.
- Validation: `tests/druid_state.lua` PASS (1205 checks),
  `tests/druid_guide_state.lua` PASS (95910 checks), luacheck 0/0 on the four
  touched files (the tree floor 2/0 untouched), **15/15 mutations killed** on
  `/tmp/opencode` copies, and the full harness **41 steps / 0 failed**. Artifact:
  `bench/druid_apl_residuals_2026-10-20.md`. **Verified offline** — no client run
  happened here.
