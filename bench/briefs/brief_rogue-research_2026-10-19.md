# Brief: rogue-research (2026-10-19)

## Objective
Enterprise-grade research to inform a future `classes/rogue.lua` module. READ-ONLY: no code changes, no TOC edits. Produce `bench/rogue_research_2026-10-19.md`.

## Context (verified on disk)
- Existing class modules: `classes/druid.lua`, `classes/hunter.lua`, `classes/paladin.lua`, `classes/shaman.lua`, `classes/warrior.lua` — read 1–2 for pattern reference only (colors/procs/on_bar_update hooks per AGENTS.md Conventions).
- Prior corpus (read BEFORE any web search — no re-searching answered questions): `bench/verify_bank.md`, `bench/discover_features.md`, `bench/competitor_scan_2026-10-17.md`, `bench/oracle_audit_2026-10-17.md`, `bench/lessons.md`, `desks/journal.md`.
- Target matrix (AGENTS.md Cross-engine): Classic Era / SoD 1.15.9 (`_Vanilla`), TBC Anniversary 2.5.6 (`_TBC`), WotLK Titanforge 3.80.2 (`_Wrath`), WoW Forever 1.60.1 + Retail 12.1.x/12.1.5 (`_Mainline`).

## Research questions (per client family)
1. Optimal DPS rotation / priority list for a top-level Rogue (single-target + cleave/AoE), including opener, cooldown stacking, and energy pooling thresholds.
2. Playstyle specifics: spec choices (e.g. Combat/Swords, Assassination, Subtlety per era), key talents/glyphs/runes, poisons, blade/kit usage, hit/expertise caps that change timing decisions.
3. Hidden techniques relevant to a swing-timer addon: swing-reset behaviors (if any), off-hand timing, energy-tick alignment with swings, Slice and Dice / Envenom / Eviscerate cutoff math, vanish/cloak timing, kick/pummel interrupt windows, threat drops.
4. What HUD/guide signals top players actually watch (energy, combo points, buff/debuff uptimes, swing) — informs what `rogue.lua` should expose via existing `on_bar_update` / guide-frame patterns.
5. Client differences: what changes between Era/SoD, TBC, WotLK, Forever, Retail for the above. Mark per-client verdicts.

## Tooling rules (mandatory)
- Enumerate BOTH catalogs first: Code-Mode `search("firecrawl")` + `search("searxng")` (or `firecrawl_find_tools`), then pick per job. Prefer SearxNG-backed searches and `extract`-style structured pulls over bare scraping.
- Keep request bodies small (prior failure mode: invalid bodies → fallback). Record every URL + what the tool returned (CAIRN: record what the tool returned, not what you hoped).
- `firecrawl_search` categories: use `developer` for code/repos, `research` for biomedical/arXiv-style only if relevant — rogue theorycraft is ordinary web; default web search preferred.
- Latest information first: prioritize current guides (2024–2026) for each client family; note patch/version and date per claim.

## Evidence bar
- Every spell/talent/id claim: CONFIRMED (source said it + citation on bench + clients it holds on) or UNCONFIRMED in caps (CAIRN remembered-id rule).
- Per-claim citations with URLs. Unconfirmed items listed separately.
- Output file: `bench/rogue_research_2026-10-19.md` (NEW file — never overwrite existing bench files). Sections: per-client rotation/priority, hidden techniques, HUD signals for addon design, spec/talent/poison tables, UNCONFIRMED list, sources.

## Boundary
- READ-ONLY except the one new bench file + own desk journal/signals. Do NOT edit classes/, TOCs, or any addon code.
- If you find conflicts between sources, record both + evidence — do not resolve by guessing. Open disagreements → note for hands-up, do not argue to death.

## Workshop mechanics (mandatory)
1. `bench-read`: journals before artifacts.
2. `desk-open`: ensure `desks/rogue-research/` exists; resume if live.
3. `desk-journal`: append entry at end.
4. `signal-write`: emit `done` (or `checkpoint` if continuing) JSON + journal marker.

## Validation owner
- Orchestrator reads `bench/rogue_research_2026-10-19.md` for per-client coverage, citation quality, UNCONFIRMED marking, and clear handoff for a future rogue-build lane.
