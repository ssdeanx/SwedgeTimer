# WeakAura Re-verify — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Re-verify the 5 WeakAuras targets with the upgraded firecrawl (camofox anti-bot + local-transformer embeddings, operator-upgraded 2026-10-19); update bench/weakaura_templates_2026-10-19.md + bench/hunter_weave_distance_2026-10-19.md ONLY where scrapes confirm or correct.
- **Scope:** READ ONLY except those two bench files. No addon/test edits, no git.
- **Next step:** enumerate firecrawl + searxng catalogs, scrape all targets with the waitFor:8000 recipe, write evidence log + bench edits.

## 2026-10-19 — Re-verify complete (done)
- **Worked on:** Enumerated catalogs (firecrawl 28 tools, searxng 4 — no new camofox/embedding paths, upgrade is server-side); scraped 6 URLs with firecrawl_scrape waitFor:8000+maxAge:0: OHhIsG8F4 CONFIRMED (D1, 3171→3172 view drift only); hw7BD9fCn CONFIRMED (D2) + hw7BD9F9Cn 404s (slug verdict: lowercase-f correct); joURtkngg CONFIRMED (D3, incl. estimator quote); eEJOoHci- CONFIRMED (Laxx weave Mod, credits Kruffz + links J3U7jOhMI); J3U7jOhMI CONFIRMED (kruffz distance aura, backpedal-only/stationary-target/custom-colors corroborate prog framing; Lua still not extracted, dynamics stay operator-reported).
- **Current state:** bench/weakaura_templates_2026-10-19.md +52 lines (§6 evidence log); bench/hunter_weave_distance_2026-10-19.md +41 lines (extraction-note correction + evidence section). No addon/test edits, no git. Screenshots not re-viewed (prior VIEWED matches stand).
- **Next step:** Orchestrator validates; in-client side-by-side owns all visual checks + prog-dynamics validation.
- [signal:done] weakaura re-verify complete, both bench files corrected/confirmed with per-URL evidence
