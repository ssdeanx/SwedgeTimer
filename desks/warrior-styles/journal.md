# warrior-styles — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Rank popular Warrior HUD / swing-timer styles (TBC + Classic Era/SoD ONLY, no Wrath) for the per-class template gallery.
- **Scope:** Read-only everywhere except NEW `bench/warrior_styles_2026-10-19.md`. No addon/test/bench edits, no git. Describe + link only, never copy proprietary code.
- **Next step:** run the research round (wago.io TBC/Era warrior suites, swing timers, guide UIs) and write the bench file.

## 2026-10-19 — Research complete, bench file written
- **Worked on:** bench-read (central journal, weakaura_templates full, hud_templates, competitor_gaps, hud_parity §0, lessons.md) → LAYOUT_KEYS (`hud.lua:125-129`) + warrior slot sets (`classes/warrior.lua:2950-2989`) pinned read-only → catalogs enumerated (firecrawl 10 tools / searxng 4, no camofox/embedding names = server-side) → 6 wago scrapes (waitFor 8000, bodies ≤ {url, waitFor}) + 2 screenshots VIEWED (ombre minimalist bar, AcidBomb 3-bar stack w/ yellow queue + `40` rage text) + negative Afenar check + wowhead chrome-only fetch.
- **Current state:** `bench/warrior_styles_2026-10-19.md` NEW on disk (single file, glob-verified absent before write). 7 ranked cards (Aurokin shout 30★/1934 installs top; AcidBomb TBC fury; ombre Era queue-colors; Krickerl SoD; google SOD timer; AQS desync code-level; cluster convention) + Afenar/Discord/Wowhead-body exclusions with reasons + 6-item shortlist (W-T1 stays default w/ queue-color gallery copy; 2 numeric/highlight borrow candidates for bars) + 17-row per-attempt log. SearXNG served nothing (rate-limited ×2); firecrawl_search invalid-body + map-status 404 recorded.
- **Next step:** orchestrator validation (no code changed, nothing to harness). In-client side-by-side owed in TESTING.md session.

## 2026-10-19 — [signal:done] warrior styles lane complete, orchestrator to validate
- NEW bench file only; 7 ranked in-scope cards + shortlist; tooling walls recorded. Signal: desks/warrior-styles/.signals/20261019T150000Z.json.
