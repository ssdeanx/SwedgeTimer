# Brief: competitor-scan — research round 2
Date: 2026-10-17. Operator directive: find future content competitors have that SwedgeTimer doesn't. Audience: 99% parsers FIRST, casuals second.

**North star (operator):** SwedgeTimer becomes the ONE-STOP SHOP — swing timer + bar addons + WeakAuras-style class HUDs + timers in one addon. Score every candidate by "would this bring a WeakAuras / Quartz / SuperSwingTimer user home", top-parser value first, casual value second.

## Read first (all verified on disk)
desks/competitor-scan/journal.md · desks/journal.md (what we're BUILDING right now — 10 lanes) · bench/discover_features.md (35 items + 5 differentiators ALREADY known — skip all of them) · bench/verify_bank.md (40 banked + competitor baselines — skip known rows) · bench/lessons.md · CAIRN.md

## What makes this round different
Previous rounds inventoried: SuperSwingTimer, TellMeWhen, Quartz, Gnosis, ClassTimer, and the 40-idea bank. Your job is NEW material only: other competitors, newer versions, wago.io suite depth, per-class "best addon" guidance, and anything a 99% parser runs that our lane plan doesn't cover. If discover_features.md or verify_bank.md already has it — DO NOT re-report it.

## Method
- Firecrawl MCP via execute (self-hosted :3002 + SearxNG). ENUMERATE FIRST: `search("firecrawl")` in Code Mode to see all 28 tools, plus firecrawl_find_tools. Pick per job — not just search+scrape: firecrawl_search (developer categories), firecrawl_scrape (single pages), firecrawl_map (URL discovery on a site like wago.io or wowhead), firecrawl_parse (structured extraction), firecrawl_agent + firecrawl_agent_status (multi-source when URLs unknown), firecrawl_developer_search (repos/code). Keep request bodies small (invalid bodies are a known failure).
- Targets (diversify, don't loop on one site): wago.io TBC/Wrath/SoD/Cata/Mists WeakAura pack pages per class (JS-rendered — if scrape fails use firecrawl_agent); Icy Veins per-class addon/guide pages TBC/Wrath/SoD + their "best addons" lists; Wowhead class guides + addon-focused pages; CurseForge searches: "swing timer", "rotation helper", "class timer", "spell timer" sorted by updated (2025–2026); Reddit (r/classicwow, r/EveryOneIsAlliance, class subreddits) parser/addon threads; WoWInterface.
- Constraints to score against: single universal build (classic-line + mainline, runtime-branching only); no non-vendored dependencies; pure logic offline-testable = high priority.

## Deliverable
bench/competitor_scan_2026-10-17.md (only this file + desk journal + signal):
- Per-source findings with URLs (cite everything; mark UNCONFIRMED explicitly, esp. Titanforge/Forever behavior and SoD ids).
- Ranked TOP-15 table: Feature | Source URL | Value for 99% parser | Value for casual | Effort (S/M/L) | Offline-testable Y/N | Overlap verdict (NEW / COLLIDES-with-lane-plan / BUILDING-now) — overlap verdicts reference desks/journal.md lanes and bench ids.
- Extend-not-repeat statement: what this round adds beyond discover_features.md in one paragraph.

## Rules
READ-ONLY on code. No git. No lint config. Small bodies. Journal entry (worked on/current state/next step) + signal (done|blocked). Final reply ≤6 lines.
