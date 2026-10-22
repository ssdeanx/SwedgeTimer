# Brief: shaman-rotation-audit (2026-10-19)

## Objective
Read-only rotation audit: what OUR shaman engine decides vs what wowsims sims say is optimal, per client. Find knowledge gaps + hidden top-100 techniques we don't model.

## In-tree (read first, verify shapes in-lane)
`classes/shaman.lua` (weave catalogue, lust status, MW stacks, totem-twist timing), `shaman_guide.lua`, `weave.lua` (breakpoint marker/clip/safe-window math, ICD), `tests/shaman_state.lua`, `tests/shaman_guide_state.lua`, `tests/weave_state.lua`, bench `verify_bank.md` (banked shaman ideas incl. S2 LvB gate, S4 rune gate), bench `competitor_gaps_2026-10-19.md` §Shaman (S1 ICD row just shipped — verify closure, don't re-audit as new).

## wowsims (external ground truth)
Enumerate BOTH tool catalogs first (Code-Mode search firecrawl + search gh_grep or equivalent; NOTE: firecrawl_search is broken on this deployment — invalid body — do NOT retry it repeatedly; firecrawl_scrape WORKS, use it on known URLs). Prefer: gh_grep code search scoped to repos wowsims/sod, wowsims/forever, wowsims/classic, wowsims/tbc-new (LB/CL weave priority, LvB windows, MW-stack spending, totem twisting, lust behavior, shock usage); firecrawl_scrape on https://github.com/wowsims/{sod,forever,classic,tbc-new} file pages; webfetch on raw.githubusercontent.com as fallback. Keep bodies small; record URL + what each tool returned.

## Compare per client (Era/SoD, TBC, Wrath, Forever, Retail)
Weave spell choice vs swing, LvB timing, MW5 instant rules, totem-twist model, Fire Nova/Earth Shock slots, lust windows, AoE (Chain Lightning/Magma), opener. For each: ours (file:line) vs sim (repo path/cite) → MATCH / GAP (ms/parse impact) / CONFLICT (evidence both sides, never guess).

## Scope
READ-ONLY except one NEW bench file + own desk. Output: NEW `bench/shaman_rotation_audit_2026-10-19.md` (confirm absent first). No code edits. No git. Per-claim CONFIRMED+citation or UNCONFIRMED.

## Mechanics (skills — CALL these tools, in order)
bench-read (journal + bench files above first) → desk-open `desks/shaman-rotation/` → desk-journal append → signal-write done JSON.

## Validation owner
Orchestrator turns gaps into build lanes; every gap needs engine file:line + sim citation + impact.
