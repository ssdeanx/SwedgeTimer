# readme-pass — Journal

## 2026-10-19 — Desk opened
- **Purpose:** CurseForge-front-page professional pass on README.md only.
- **Scope:** README.md (TESTING.md touch-up only if the red-zone copy needs a checklist line — prefer leaving it; no other files; no git).
- **Sources read first:** README.md (full), bench/rogue_readiness_2026-10-19.md §§1-3, desks/journal.md Status; TESTING.md rogue section (73-91) checked before deciding on TESTING edits.
## 2026-10-19 — README professional pass done
- **Worked on:** Rewrote README.md (235 → 63 lines) for a first-time CurseForge downloader: what it does, client table, install, 30-second setup, per-class tour, defaults/limits, links. Removed dev-facing sections (Architecture, Tech Stack, Scripts, Deployment, Contributing) — wrong audience for the front page.
- **Current state:** Every behavior claim pinned (toc:1, TESTING:10-16/126-129/73-91, main.lua:1705-1734, config_presets.lua:576-627, classes/rogue.lua:711-721/579/1178, practice.lua:2554+) or marked UNCONFIRMED/in-client (whole rogue section). TESTING.md left untouched — its rogue lines 77-79 already cover the red SS window ("reads correctly"), no checklist line needed.
- **Next step:** Orchestrator validation (pins + any claim to cut or mark).

## 2026-10-19 — [signal:done] README pass complete
- README rewritten; TESTING untouched; no other files; no git.

## 2026-10-19 — CurseForge README + TOC icon wiring (done)
- **Worked on:** Rewrote README.md (63 → ~60 lines, download-decision page: 1-line pitch, client table, PENDING screenshots, CurseForge+manual install, /st commands verified main.lua:1716-1756, per-class one-liners, plain-text project links, license corrected MIT→GPL-3.0 per LICENSE file). Added `## IconTexture: SwedgeTimer_v2_transparent.tga` after Notes in all 7 TOCs; CRLF preserved, Interface/Version (2.1.1) untouched. Research: enumerated firecrawl (28 tools) + searxng (4 tools) catalogs; searxng carried (firecrawl_search broken per bench/lessons.md); warcraft.wiki.gg TOC_format pins IconTexture syntax + Displayed-icons placement; classic_era AddonList.lua:376-387 pins client resolution via GetAddOnMetadata→texture markup.
- **Proven:** harness 38/0, luacheck 2/0 (floor, both KEEP-ruled), toc_check PASS, `file` confirms 7/7 CRLF, IconTexture 1/1 in each toc, logo present at root (1024x1024 RGBA TGA). No code/tests/docs touched; no git.
- **CurseForge gotchas (for orchestrator):** plain markdown only (headers/tables/lists/code) — zero raw HTML; no shields badges (need `<object>`, break in markdown); no image URLs (nothing to point at) — screenshots section is text-only PENDING so nothing renders broken; no invented links — project pages plain text until URLs confirmed.
- **Next step:** Orchestrator validation (pins + any claim to cut or mark).
