# Brief: rogue-deep-research (2026-10-19)

## Objective
Second rogue research pass — go deeper where the first pass (`bench/rogue_research_2026-10-19.md`) stopped. READ-ONLY: no addon code edits. Output: NEW file `bench/rogue_deep_2026-10-19.md`.

## Must-answer questions (all NEW vs the first pass — read it first, do not re-derive it)
1. **Hidden / speedrun / top-100 technique:** energy-tick alignment with swing timer, Sinister Strike timing relative to MH swing in Classic (owner recall: "SS after MH swing" — CONFIRM or REFUTE with a cited source, state which client/patch it holds on), Thistle Tea / Lay on Hands-style consumes in parse runs, vanish-immunity tricks, weapon-swap macros, opener sequencing in speedruns, AR+BF stacking windows, Blade Flurry cleave positioning.
2. **Competitor teardown for rogues:** what WeakAuras rogue packages track (energy tick, SnD/rupture bars, swing), what other swing timers show for rogues (e.g. SuperSwingTimer rogue set per `bench/discover_features.md` §Rogue — extend, don't repeat), rogue-specific addons (energy tick trackers, CP builders) and which of their signals map to our `on_bar_update` / guide-frame patterns.
3. **Addon-design handoff:** for each confirmed technique, state exactly which addon signal it needs (swing phase, energy-tick phase, aura uptime, cooldown state) and whether the existing five-class patterns (`ST.<CLASS>.gather_guide_inputs` frozen-spec + live reads, `bars.lua` per-frame hook) already expose it or a new probe is needed. Flag anything needing a CLEU shape (poison/Shiv/Vanish) against oracle R1 (Anniversary name-vs-id).

## Tooling (mandatory)
- Enumerate BOTH catalogs first (Code-Mode `search("firecrawl")` + `search("searxng")`, or `firecrawl_find_tools`), prefer SearxNG-backed searches + extract-style structured pulls, keep request bodies small, record every URL + what the tool returned.
- Sources: 2024–2026 speedrun/parse guides, top-log breakdowns (Warcraft Logs analyses), WeakAuras listing pages (wago.io), addon repos (CurseForge/WoWI/GitHub), class Discords where publicly indexed. Per-claim CONFIRMED+citation+clients or UNCONFIRMED in caps.

## Boundary
- READ-ONLY except one new bench file + own desk journal/signals. Do NOT edit classes/, TOCs, or tests. Do NOT duplicate `bench/rogue_research_2026-10-19.md` — supersede/extend with pointers.
- Open conflicts recorded with evidence, never guessed.

## Workshop mechanics (mandatory — skills: bench-read, desk-open, desk-journal, signal-write)
1. bench-read: `desks/journal.md`, `bench/rogue_research_2026-10-19.md`, `bench/verify_bank.md`, `bench/discover_features.md`, `bench/competitor_scan_2026-10-17.md`, `bench/lessons.md`.
2. desk-open: ensure `desks/rogue-deep/` exists; resume if live.
3. desk-journal append + signal-write `done` JSON at end.

## Validation owner
- Orchestrator reads `bench/rogue_deep_2026-10-19.md` for SS-after-swing verdict, competitor signal map, per-technique addon handoff, citation quality.
