# Brief: rogue-rotation-audit (2026-10-19)

## Objective
Read-only rotation audit: what OUR rogue engine decides vs what wowsims sims say is optimal, per client. Find knowledge gaps + hidden top-100 techniques we don't model.

## In-tree (read first, verify shapes in-lane)
`classes/rogue.lua` (provider gather + on_bar_update), `rogue_guide.lua` (pure decision model: pooling bands, Rupture-vs-Eviscerate on TTD, per-client Envenom tables, EA/Shiv/Tea rules), `tests/rogue_state.lua`, `tests/rogue_guide_state.lua`, bench `rogue_research_2026-10-19.md` + `rogue_deep_2026-10-19.md` (SS-after-MH CONFIRMED Era / REFUTED TBC, tick predictor, competitor teardown §3-4).

## wowsims (external ground truth)
Enumerate BOTH tool catalogs first (Code-Mode search firecrawl + search gh_grep or equivalent; NOTE: firecrawl_search is broken on this deployment — invalid body — do NOT retry it repeatedly; firecrawl_scrape WORKS, use it on known URLs). Prefer: gh_grep code search scoped to repos wowsims/sod, wowsims/forever, wowsims/classic, wowsims/tbc-new (rotation APL/sim core per class); firecrawl_scrape on https://github.com/wowsims/{sod,forever,classic,tbc-new} file pages; webfetch on raw.githubusercontent.com file URLs as fallback. Keep every request body small; record every URL + what the tool returned.

## Compare per client (Era/SoD, TBC, Wrath, Forever, Retail)
Action priority, pooling/snapshot rules, finisher cutoffs, Envenom handling, EA duty, Shiv upkeep, Tea usage, opener, AoE/cleave, energy-tick alignment, swing-timing. For each: what our engine does (file:line) vs what the sim does (repo path/cite) → MATCH / GAP (with ms/parse impact) / CONFLICT (evidence both sides, never guess).

## Scope
READ-ONLY except one NEW bench file + own desk. Output: NEW `bench/rogue_rotation_audit_2026-10-19.md` (confirm absent first). No code edits. No git. Per-claim CONFIRMED+citation or UNCONFIRMED.

## Mechanics (skills — CALL these tools, in order)
bench-read (journal + the bench files above first) → desk-open `desks/rogue-rotation/` → desk-journal append → signal-write done JSON.

## Validation owner
Orchestrator turns gaps into build lanes; every gap needs engine file:line + sim citation + impact.
