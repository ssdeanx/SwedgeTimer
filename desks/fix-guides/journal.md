# fix-guides — Journal

## 2026-10-19 — Desk opened (brief fix-guides-weave)
- **Purpose:** writer lane for the guides/weave/class-module half of the feature-hunter audit plus the proctor G1–G6 gaps.
- **Scope:** weave.lua, nextaction.lua, nextaction_ui.lua, compat.lua (observability only), classes/paladin.lua, classes/shaman.lua, classes/hunter.lua (R4 line only), the eight named test suites. NO main.lua / bars.lua / swing_source.lua / enemy_swing.lua / TOCs / version / CHANGELOG (fix-engine-dispatch).
- **Baseline:** 35 steps, 0 failed; luacheck 2/0.
- **Next step:** execute the brief.

## 2026-10-19 — [signal:done] fix-guides-weave complete
- **Worked on:** H4 (unknown-cast split in weave.lua + shaman hide paths), M3 (unmatched-payload counter + one-time notice), M4 (distinct "seal data unknown" band state; mirror-failure case cited, not invented), M5 (compat `api.auras_may_be_secret` probe + "lust unknown" band text behind the existing opt-in), M6 (`inputs_unknown` threaded engine → provider → UI "…"), plus proctor G1 (Cata/Mists smoke profiles + read-only main boot asserting inert-standin), G2 (lust→band width), G3+G6 (lag defaults 1.4/15, custom, nil fallback, deadzone independence static+behavioral), G4 (combat transitions keep the mainhand cycle, one hook call), G5 (3 weave cross-term cases). Hunter R4 line was already `== true` — no code change, pin added.
- **Current state:** harness **35 steps, 0 failed**, luacheck **2 warnings / 0 errors** (floor). Mutation battery 15/15 bitten on `/tmp/opencode/mut_guides` (script `/tmp/opencode/muts_guides.py`); post-restore copy green. Report: `bench/fix_guides_weave_2026-10-19.md`. Files changed: weave.lua, nextaction.lua, nextaction_ui.lua, compat.lua, classes/paladin.lua, classes/shaman.lua, tests/{weave_state,nextaction_state,guide_contract,secret_guard_state,paladin_state,shaman_state,hunter_state,smoke}.lua.
- **Next step:** orchestrator reconciles against fix-engine-dispatch (no shared files); then the owner in-client TESTING.md pass. Residuals: diag.lua was out of scope, so M3's counter / M5's regime flag are not yet printed by `/st diag`.
