# Shaman-Druid Name-vs-Id — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Apply the operator name-vs-id rule (bench/lessons.md) repo-wide for shaman + druid: TBC Anniversary resolves by NAME never bare id, Classic Era by id; pin both.
- **Scope (code):** classes/shaman.lua, shaman_guide.lua, classes/druid.lua, druid_guide.lua, tests/shaman_state.lua, tests/shaman_guide_state.lua, tests/druid_state.lua, tests/druid_guide_state.lua. No weave/druid_energy (pure, read-only), no compat (rogue lane), no hunter files (WA-consume lane), no git, no invented ids.
- **Next step:** implement spell_query branching + name constants, extend fixtures, pin both resolutions, harness + luacheck + mutations on /tmp/opencode copies.

## 2026-10-19 — Name-vs-id wired, both resolutions pinned
- **Worked on:** bench-read (journal + bench + lessons + briefs); spell_query helper + TBC name constants in classes/shaman.lua (catalogue label path, SS/SR/shock/Fire Nova/cooldowns, known gates, HUD/rotation TBC name maps, SUCCEEDED live-name bridge kept nil-safe) and classes/druid.lua (Maul/Mangle cost + queue hooks, resolve_cooldown_query/spell_data_resolves/hud_slot_name/rotation TBC maps, guide/HUD icon re-point on TBC, SoD probes left ERA-gated); fixtures extended for name+id in tests/shaman_state.lua + tests/shaman_guide_state.lua (highest-known-rank name answers, name-keyed cooldowns/known); §31 pins in shaman_state (SS cooldown + catalogue) and druid_state (Maul queue/cost/slots); static no-api-call pins in both guide_state suites.
- **Current state:** in-scope suites green — shaman_state 482, druid_state 509, shaman_guide_state 843, druid_guide_state 95462; luacheck floor 2/0 restored (own 8 warnings wired/removed); endings preserved (shaman LF, druid CRLF); mutations 6/6 KILLED on /tmp/opencode/nameid-muts copies (m1 gather-SS-id, m2 catalogue-id-walk, m3 Maul-cost-id, m4 IsCurrentSpell-id, m5/m6 pure static); tree untouched by mutation phase (all writes in /tmp). Full harness 36/38: the 2 reds are out-of-scope paladin crossfire (guide_contract CS 999/4 + hud_state CS/Wings nils, classes/paladin.lua mid-edit by another lane) — not this lane's files, left for the orchestrator reconcile.
- **Next step:** orchestrator validates + reconciles (guide_contract/hud_state crossfire, count pins) + dispatches in-client confirmation; owner in-client test session per TESTING.md owns all UNCONFIRMED ids.

## 2026-10-19 — [signal:done] name-vs-id wired + pinned
- in-scope 482/509/843/95462 green, luacheck 2/0, 6/6 mutations killed on /tmp/opencode/nameid-muts; full harness 36/38 (2 out-of-scope paladin reds left for reconcile); desks/shaman-druid-nameid/.signals/20261019T175204Z.json
- Validation owner: orchestrator.
