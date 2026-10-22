# shaman-rotation — Journal

## 2026-10-19 — Desk opened
- **Purpose:** shaman rotation vs wowsims sims, per client. Find gaps and hidden techniques.
- **Scope (read only):** classes/shaman.lua, shaman_guide.lua, weave.lua, tests/shaman_state.lua, tests/shaman_guide_state.lua, tests/weave_state.lua. Sim sources: wowsims/sod, wowsims/forever, wowsims/classic, wowsims/tbc-new, wowsims.github.io.
- **Next step:** read our six files, then sim rotation code per client, then write bench/shaman_rotation_audit_2026-10-19.md.

## 2026-10-19 — Rotation audit vs wowsims done
- **Worked on:** read all six in-scope files; pulled sim rotations via firecrawl_scrape (tree/APL pages), web_url_read (raw APL/test files) and shell curl (Go spell sources, proto). SoD P4/P6 APLs, classic default APL, TBC default APL, Forever testing.build.json rotation, WF ICD per repo (SoD 1.5s, classic 1.5s, TBC 3s), rune-id map from sod proto/shaman.proto, SS/FS/FN/Magma numbers from sim Go sources.
- **Current state:** bench/shaman_rotation_audit_2026-10-19.md written. Headline: rule-7 WAIT hold contradicts all four sims; SoD Feral Spirit/Lava Lash/Molten Blast missing; ERA FS over-prompt; TBC Magma + FN-while-FE + buff-keyed twist gaps; WF ICD 1.5s on Era/SoD vs hardcoded 3s; Wrath uncovered (no wotlk repo in scope).
- **Next step:** orchestrator validation + dispatch of fix lanes; open question rack: remove vs opt-in for WAIT hold.

## 2026-10-19 — [signal:done] rotation audit on the bench
- bench/shaman_rotation_audit_2026-10-19.md; signal desks/shaman-rotation/.signals/20261019T094500Z.json
- Validation owner: orchestrator.
