# Brief: hunter-rotation-audit (2026-10-19)

## Objective
Read-only rotation audit: what OUR hunter engine decides vs what wowsims sims say is optimal, per client. Find knowledge gaps + hidden top-100 techniques we don't model.

## In-tree (read first, verify shapes in-lane)
`classes/hunter.lua` (H2 Steady-spam/rotation logic, lust-gated cues, ToT warning just shipped), `hunter_guide.lua`, `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`, bench `verify_bank.md` (banked hunter ideas), bench `competitor_gaps_2026-10-19.md` §Hunter (HST precedents: clip counter, latency buffer, ToT — verify closure, don't re-audit as new).

## wowsims (external ground truth)
Enumerate BOTH tool catalogs first (Code-Mode search firecrawl + search gh_grep or equivalent; NOTE: firecrawl_search is broken on this deployment — invalid body — do NOT retry it repeatedly; firecrawl_scrape WORKS, use it on known URLs). Prefer: gh_grep code search scoped to repos wowsims/sod, wowsims/forever, wowsims/classic, wowsims/tbc-new (steady/weave shot priority, haste plateaus, Aimed/Multi weaving, pet handling, lust windows, clip avoidance); firecrawl_scrape on https://github.com/wowsims/{sod,forever,classic,tbc-new} file pages; webfetch on raw.githubusercontent.com as fallback. Keep bodies small; record URL + what each tool returned.

## Compare per client (Era/SoD, TBC, Wrath, Forever, Retail)
Shot priority/rotation, Steady clipping vs haste, Aimed/Multi weave slots, Kill Command/Multi timing, pet + BW windows, lust behavior, AoE, opener. For each: ours (file:line) vs sim (repo path/cite) → MATCH / GAP (ms/parse impact) / CONFLICT (evidence both sides, never guess).

## Scope
READ-ONLY except one NEW bench file + own desk. Output: NEW `bench/hunter_rotation_audit_2026-10-19.md` (confirm absent first). No code edits. No git. Per-claim CONFIRMED+citation or UNCONFIRMED.

## Mechanics (skills — CALL these tools, in order)
bench-read (journal + bench files above first) → desk-open `desks/hunter-rotation/` → desk-journal append → signal-write done JSON.

## Validation owner
Orchestrator turns gaps into build lanes; every gap needs engine file:line + sim citation + impact.
