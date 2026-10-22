# warrior-rotation — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Read-only rotation audit: our warrior engine vs wowsims sims, per client. Find gaps + hidden top-100 techniques we don't model.
- **Scope:** classes/warrior.lua, warrior_guide.lua, tests/warrior_state.lua, tests/warrior_guide_state.lua (read-only); one NEW bench file only. No code edits. No git.
- **Next step:** read branch brief + in-tree files, enumerate tool catalogs, pull wowsims sim sources, write bench/warrior_rotation_audit_2026-10-19.md.

## 2026-10-19 — Rotation audit done
- **Worked on:** read classes/warrior.lua (full), warrior_guide.lua (full), both test suites (headers + matrix pins); pulled 14 sim files (4 APL pairs + Go mechanics) via firecrawl_scrape trees + webfetch raw; gh_grep repo-scoped search unproductive, firecrawl_search not retried per brief, GitHub API 403, wowsims.github.io is a Vite shell (no sim content).
- **Current state:** NEW bench/warrior_rotation_audit_2026-10-19.md on disk. Headline: ww_ids OP-rank contamination (HIGH), TBC HS ranks 29707/30324 missing + wrong MS comment (HIGH), SoD Blood Surge aura 413399 unmatched (HIGH); floors conflict 40-vs-ours on all clients; hamstring weave + sunder upkeep + stance system unmodeled; Victory Rush and all Wrath specifics stay UNCONFIRMED.
- **Next step:** orchestrator turns ranked gaps X1-X16 into build lanes; every gap carries engine file:line + sim citation + impact.

## 2026-10-19 — [signal:done] audit on bench
- bench/warrior_rotation_audit_2026-10-19.md written; 3 HIGH gaps cited, Wrath + Victory Rush + 10 custom ids UNCONFIRMED.
