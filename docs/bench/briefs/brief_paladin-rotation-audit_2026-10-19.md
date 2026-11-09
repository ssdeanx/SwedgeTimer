# Brief: paladin-rotation-audit (2026-10-19)

## Objective
Read-only rotation audit: what OUR paladin engine decides vs what wowsims sims say is optimal, per client. Find knowledge gaps + hidden top-100 techniques we don't model.

## In-tree (read first, verify shapes in-lane)
`classes/paladin.lua` (twist state machine, next-action provider gather), `twist.lua` (twist window/attempt/success/impossible — WoW-free), `nextaction.lua` (rotation-pattern tables + decision model), `tests/twist_state.lua`, `tests/nextaction_state.lua`, `tests/paladin_state.lua`, bench `verify_bank.md` (banked paladin ideas P1-P7 + corrections), `bench/competitor_scan_2026-10-17.md` §1 (SST reseal marker precedent).

## wowsims (external ground truth)
Enumerate BOTH tool catalogs first (Code-Mode search firecrawl + search gh_grep or equivalent; NOTE: firecrawl_search is broken on this deployment — invalid body — do NOT retry it repeatedly; firecrawl_scrape WORKS, use it on known URLs). Prefer: gh_grep code search scoped to repos wowsims/sod, wowsims/forever, wowsims/classic, wowsims/tbc-new (ret/seal-twist APL, Crusader Strike priority, seal/judgement logic); firecrawl_scrape on https://github.com/wowsims/{sod,forever,classic,tbc-new} file pages; webfetch on raw.githubusercontent.com as fallback. Keep bodies small; record URL + what each tool returned.

## Compare per client (Era/SoD, TBC, Wrath, Forever, Retail)
Seal-twist windows, CS timing, judgement refresh, Consecration/Exorcism filler rules, lag calibration, lust-narrowed windows, AoE, opener. For each: ours (file:line) vs sim (repo path/cite) → MATCH / GAP (ms/parse impact) / CONFLICT (evidence both sides, never guess).

## Scope
READ-ONLY except one NEW bench file + own desk. Output: NEW `bench/paladin_rotation_audit_2026-10-19.md` (confirm absent first). No code edits. No git. Per-claim CONFIRMED+citation or UNCONFIRMED.

## Mechanics (skills — CALL these tools, in order)
bench-read (journal + bench files above first) → desk-open `desks/paladin-rotation/` → desk-journal append → signal-write done JSON.

## Validation owner
Orchestrator turns gaps into build lanes; every gap needs engine file:line + sim citation + impact.
