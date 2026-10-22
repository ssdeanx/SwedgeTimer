# perclient-api-truth — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Produce the **verified per-client API truth table** for the addon (19 checks:
  API — branch — file:line — quoted definition — arity/return shape — verdict), for the
  branches `classic_era` (checked out), `classic_anniversary`, `classic_titan`,
  `origin/forever`, `live`. This is the last evidence the read-only publish-gate re-audit
  could not produce itself (no shell; `read`/`grep` are blocked on `/home/sam/wow-ui-source`;
  `ast_grep_search` reaches only the checked-out branch). Then fix the two wrong citations
  (L-2, L-3) and the label defect (L-4) the re-audit found.
- **Scope:** READ WRITE — `compat.lua`, `classes/rogue.lua` (only the `GetItemInfo`
  return-name usage), `tests/secret_guard_state.lua` (pins), NEW
  `bench/perclient_api_truth_2026-10-20.md`, and `bench/compat_m3_contract_2026-10-20.md`
  (the one bench file whose claim is wrong). Everything else is READ ONLY. No git in this
  repo; `git -C /home/sam/wow-ui-source show <branch>:<path>` is read-only reference
  inspection — never checkout. No lint-config changes.
- **Next step:** run the 19 checks branch by branch against `/home/sam/wow-ui-source` via
  `git show`, record the evidence, write the truth table, then land L-2/L-3/L-4 and
  re-run the harness + luacheck + mutation proofs on `/tmp/opencode` copies.

## 2026-10-20 — The truth table landed; L-2 and L-4 closed, L-3 refuted
- **Worked on:** all 19 checks run on **all five branches** (`classic_era`,
  `classic_anniversary`, `classic_titan`, `origin/forever`, `live`) of
  `/home/sam/wow-ui-source`, read-only via `git show <branch>:<path>` + `git grep
  <branch>` (never a checkout — the reference repo is not ours). Wrote
  `bench/perclient_api_truth_2026-10-20.md`: one row per API × branch with the
  `branch:file:line` + the quoted definition, the arity/return shape the addon relies on,
  and a verdict per API. **No API in the checklist needs a gate on any branch**; two need a
  documented nuance (the `UnitAura` global is classic-gated and absent on Retail/Forever —
  the `C_UnitAuras` path already answers there; the totem slot constants are not defined
  as globals on the WoW Forever client because that branch's `Constants.lua` is
  mainline-gated — the addon hard-codes 1/2/3/4, so nothing to do).
- **Current state:** three findings closed — **L-2 confirmed and fixed** (the totem
  citation was wrong: the real file is `Blizzard_FrameXMLBase/Classic/Constants.lua` and
  the block is **286-289** on the classic branches, `:226-229` on forever, `:241-244` on
  live; the comment now cites all three and says the constants are evidence, not a runtime
  dependency); **L-4 confirmed and fixed** (the wrapper's 6th/7th locals were named
  `class, subclass` — the classic global's naming — while the preferred probe
  `C_Item.GetItemInfo` returns `itemType`/`itemSubType` there on **every** branch; the
  wrapper and the rogue's `item_subclass` helper now use the normalised names
  `item_type`/`item_sub_type` and the contract is stated in the file); **L-3 REFUTED**
  (the bench claim was right and the re-audit's premises were wrong —
  `SpellBookDocumentation.lua:82` on `classic_era` **does** carry `Name = "IsSpellKnown",`,
  and `loadDeprecationFallbacks` occurs in **33 files** on `classic_era`, 40 on `live`; the
  §5 claim is kept, re-cut with the per-branch evidence and a dated correction note).
  Two new facts the re-audit did not reach are recorded: `C_SpellBook.IsSpellKnownOrInSpellBook`
  **is** present on `classic_era` (`:98`), and the classic global answers
  `IsSpellInSpellBook(..., includeOverrides = false)`, not `IsSpellKnown`.
- **Proof:** harness **41 steps / 0 failed**; luacheck **2 warnings / 0 errors** (the
  floor, 83 files); `tests/secret_guard_state.lua` **433 checks** (was 410 — the new
  §13c-bis L-4 contract pins and §13c-ter L-2 citation pins); behavioural equivalence
  old-locals vs current `compat.lua` **15 checks / 0 failed** (3 probe shapes × 3 items:
  the returned tuple is identical — the L-4 change is label-only); mutation proofs
  **14/14 killed** (`/tmp/opencode/mut/run.sh`, on copies, baseline passes first).
- **Anomaly recorded, not smoothed over:** the FIRST harness run of this lane printed
  `luacheck . (Total: 7 warnings / 0 errors in 83 files)` with every test step green.
  Nothing on disk changed between that run and the next, and three direct `luacheck .`
  runs plus two full `tests/run.sh` runs then read the standing 2/0 floor. Most likely a
  parallel lane mid-edit in the shared tree (the same crossfire the `compat-m3` desk
  journal recorded) — recorded in the bench file §5.1 because a fluctuating lint count is
  exactly what the floor exists to catch.
- **Next step:** none for this desk — the three findings are closed and pinned, and the
  truth table is on the bench. If the operator wants the L-3 correction recorded
  elsewhere (the re-audit's own file is not on disk), the bench note
  `bench/perclient_api_truth_2026-10-20.md` §4.2 and `bench/compat_m3_contract_2026-10-20.md`
  §5.1 carry the refutation with citations.

## 2026-10-20 — [signal:done] the truth table landed; L-2 and L-4 closed, L-3 refuted
- `desks/perclient-api-truth/.signals/2026-10-20T11-40-00Z-done.json` — all 19 checks
  answered with `branch:file:line` + a quoted definition on all five branches; the truth
  table is `bench/perclient_api_truth_2026-10-20.md`; L-2 and L-4 are closed and pinned;
  L-3 is refuted and the bench claim re-cut with per-branch evidence. Harness 41/0,
  luacheck 2/0, `secret_guard_state.lua` 433 checks, equivalence 15/0, mutations 14/14.

## 2026-10-20 — [signal:hands-up] HU-17 raised
- `desks/perclient-api-truth/.signals/2026-10-20T11-41-00Z-hands-up.json` + the HU-17 row
  in `hands-up.md` — the brief's L-3 instruction was **not** followed as written, because
  the bench claim it asked to "re-cut" is verifiably TRUE and the brief's premises
  (`SpellBookDocumentation.lua:82` carries no `IsSpellKnown` on `classic_era`;
  `loadDeprecationFallbacks` appears nowhere in the tree) are both false. The operator
  rules on the deviation; the bench file is correct and pinned under either reading.
  NOT BLOCKING: the deliverable is complete and green either way.

