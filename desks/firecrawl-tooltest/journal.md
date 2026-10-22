# firecrawl-tooltest — Journal

## 2026-10-19 — Desk opened
- **Purpose:** TEST upgraded firecrawl deployment (local-transformers embeddings, camofox fixed) — prove which tools work with CORRECT calls, record working call shapes.
- **Scope:** READ ONLY except NEW file bench/firecrawl_tooltest_2026-10-19.md (verified absent via glob 2026-10-19).
- **Next step:** enumerate full firecrawl catalog via execute search(), then test extract/search/agent with minimal valid bodies, ≥3 shaped attempts per tool before declaring broken.

## 2026-10-19 — Tooltest complete
- **Worked on:** enumerated all 28 firecrawl tools (no standalone extract tool exists — explains prior-lane failures); proved scrape §1b recipe (`formats+waitFor:3000`, never stealth) on wago.io; search broken 5/5 shapes, agent 3 attempts, dev 404, credit 500, query/json LLM layer down, map degraded-empty.
- **Current state:** bench/firecrawl_tooltest_2026-10-19.md written (recipes + broken list + latency classes). No addon/test edits, no git.
- **Next step:** orchestrator validates; research lanes keep SearxNG as search carrier, Firecrawl scrape-by-URL only.

## 2026-10-19 — [signal:done] tooltest filed
- bench/firecrawl_tooltest_2026-10-19.md + .signals/2026-10-19T000000Z.json. Validation owner: orchestrator.
