# range-api-matrix — Journal

## 2026-10-21 — Desk opened (read-only research lane, brief_range-api-matrix_2026-10-21)
- **Purpose:** settle the client-API facts the range fix depends on: which range
  APIs exist per client family, and which are PROTECTED (addon call ->
  ADDON_ACTION_BLOCKED). One bench report, no code edits.
- **Scope (as briefed):** classic_era observations (ast-grep over  /home/sam/wow-ui-source), web context (protected-API list), LRC API-call audit.
  OUT: code edits, git, lint config, TOCs, the fix itself.
- **Next step:** bench-read (journal + bench/lessons.md) -> desk-open -> ast-grep +
  web -> bench/range_api_matrix_2026-10-21.md -> journal -> signal:done.
- **Tooling note (recorded early):** this lane has NO write tool — Code Mode catalog
  search returns {"items":[]} for every query (incl. "searxng"/"firecrawl") and the
  outer toolset is read-only. The bench file, this journal and the signal are
  therefore handed to the orchestrator verbatim for filing, per the brief's
  fallback clause.

## 2026-10-21 — Worked on
- **bench-read:** read `bench/briefs/brief_range-api-matrix_2026-10-21.md`,
  `desks/journal.md`, `bench/lessons.md`. Re-learned: ast-grep cannot see string
  literals inside table constructors (a sweep miss is not an absence); a bench
  citation's line number is a claim — re-read the source; firecrawl_search is
  broken on this deployment.
- **Classic_era observations (ast-grep over the checked-out branch):**
  `C_SpellBook.IsSpellBookItemInRange` 0 hits (field, call, subscript forms);
  `C_Spell.IsSpellInRange` 1 callsite (Blizzard_CooldownViewer/CooldownViewer.lua:713,
  one argument = spell ID, result compared `== false`); `IsItemInRange` 2 hits
  (Deprecated_ItemScript.lua:29 alias + the generated doc).
- **Gap-closer:** ast-grep cannot see strings, so I added Sourcegraph full-repo
  plain-text search on upstream `classic_era` (sha 8165d4cd): "IsSpellBookItemInRange"
  = 0 matches (closes the string-literal hole), "IsItemInRange" = 2, "IsSpellInRange"
  = 2 (matches the local counts). Also fetched upstream raw files for
  classic_era/live/forever via GitHub raw to read Blizzard's generated API docs
  (the string tables ast-grep cannot see): SpellDocumentation.lua:601-614,
  ItemDocumentation.lua:923-935, SpellBookDocumentation.lua (87 classic_era
  entries, 266 live; IsSpellBookItemInRange only on live:596 / forever:616),
  RestrictedActionsDocumentation.lua (CheckAllowProtectedFunctions + the
  ADDON_ACTION_BLOCKED payload) and the 11.0 spellbook transition guide
  (live/forever:46-47).
- **Web (context only):** warcraft.wiki.gg pages for API:IsItemInRange,
  API:C_Item.IsItemInRange, API:C_Spell.IsSpellInRange, API:IsSpellInRange,
  ADDON_ACTION_BLOCKED. wiki.gg was intermittently offline (502) during the round.
- **LRC API-call audit** of the vendored LibRangeCheck-2.0: captures at :420-422,
  guards at :441/:447, reachability at :596/:610/:803, dead call sites at
  :512/:809 (item) and :477/:495/:826/:842 (spell), interact-only survivor.
  Also read compat.lua:915-941 and main.lua:1783-1824 for the call path.

## 2026-10-21 — Scope correction received (orchestrator)
- The orchestrator filed the shell-verified cross-branch matrix
  (`bench/range_api_orchestrator_matrix_2026-10-21.md`) and ruled: branch-specific
  claims must carry their branch; web = CONTEXT ONLY (a wiki "protected" claim is not
  proof for the 1.15.x classic backport; the operator's in-client report is the only
  proof of a block); the modern spell path (R3) stays DEFERRED and no finding may
  justify wiring it; "C_Spell.IsSpellInRange looks safe" must be filed as an OPEN
  FOLLOW-UP with an exact command; and the LRC's legacy capture + item tables are
  upstream design, while CALLING the item-range API where it is blocked with an
  invalid call shape is not.
- Re-wrote the report against those rules: no branch is generalised, every wiki
  citation is labelled CONTEXT ONLY, the modern spell API appears only as FU-1
  (open follow-up + exact command) and never as a justification, and §4.3 splits
  "by design" from "not by design".

## 2026-10-21 — Lane complete (report handed over)
- **Current state:** report text ready for `bench/range_api_matrix_2026-10-21.md`
  (file did not exist before this lane; confirmed by glob). No repo file was  modified; no code edits, no git, no lint-config changes. Three open follow-ups
  (FU-1, FU-2, FU-3) and seven named gaps (G1-G7) are inside the report.
- **Next step:** orchestrator files the bench file + this journal + the signal,
  then the range-fix lane decides the path with FU-1/FU-2 queued for the next
  in-client session (the operator declined the probe on 2026-10-21).
- [signal:done] 2026-10-21 — `.signals/2026-10-21T12-00-00Z-done.json`
  (report + journal + signal handed over as text; desk had no write tool).
