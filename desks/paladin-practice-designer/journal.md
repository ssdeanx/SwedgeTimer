# Paladin Practice + Designer — Journal

## 2026-10-19 — Desk opened
- **Purpose:** FULLY implement practice + designer for PALADIN: (1) paladin drills in the practice.lua registry must start/run/grade from /st practice and from a top-level Practice options tab — build whatever is missing (routing, tab, hooks), pin it; (2) every element paladin creates must be positionable in design mode — build whatever is missing, pin it.
- **Scope:** classes/paladin.lua, nextaction.lua, tests/paladin_state.lua, tests/nextaction_state.lua fully owned. Shared files (option_tables.lua, practice_ui.lua, practice.lua, designmode.lua) READ fully; edit ONLY paladin-keyed regions + the new Practice group shell if absent.
- **Out of scope:** other classes' files; bars, compat, main, hud, diag, guide_contract, run.sh, TOCs, versions, README, CHANGELOG, docs; no git commits; no lint-config changes; no invented integrations; Victory Rush stays CUT.
- **Operator constraint (2026-10-19):** practice runs how it has always run (panel icons cast simulated spells, /st practice toggles the session). Extend that existing flow to paladin — no new practice flow or invocation pattern.
- **Baseline:** tree 38/0 green (verified 2026-10-19 in-lane); luacheck floor 2/0.
- **Next step:** audit harness combo helpers + sim AW keys + paladin options practice section + designer element audit, then build.

## 2026-10-19 — Steers absorbed, audit complete
- **Steers (all operator):** (1) extend existing panel-icons + /st practice flow, no new invocation; options Practice toggle is the invocation. (2) Paladin practice behavior byte-identical; verify + pin; designer half is the build; paladin options section stays byte-intact (zero edits to class_opts_funcs.PALADIN). (3) Archive pattern: TBC ≡ Forever file-identical (one pattern); Practice page = "Guides & Practice" > "Practice Mode" with Simulation/Boss/Rotation&Timeline/Feedback tabs, both invocations; shown to all classes. (4) Designer pattern: archive editmode ELEMENTS 311-539, 9 descriptors; diff vs paladin, close gap per key/title/frame/enable_path/card/settings/save/reset. (5) Branch-verify every touched API on Era/TBC/Forever via read-only git show; unknown hides, never throws.
- **Audit outcome (designer):** current registry covers mainhand/offhand/ranged bars, hud, rottext, nag, practice_panel/rotation/timeline (7 of archive 9, adapted). GAPS: seal icons (vf.seal_icons, bar child) + success text (vf.twist_text, bar child) — archive registers both as independent elements. Effects chip (virtual) CANNOT register: design.lua normalise REQUIRES get_frame; no card/settings infra in current designmode (header documents as not-ported) — FILED for cards-infra lane with rationale.
- **Known crossfire:** tests/designmode_state.lua:546 pins registry count 9 — adding seal_icons + success_text makes 11. That file is out of scope (no edits); flagged as orchestrator reconcile (mechanical pin update). Verified my get_frame is pcall-wrapped + nil-safe so no other designmode_state breakage expected.
- **Plan:** paladin.lua (detach apply/save/reset + setup branches + design force-show, all nil-default-attached); designmode.lua (+2 paladin descriptors); option_tables.lua (top-level Practice page only, paladin section untouched); practice_ui.lua (start seeding + AW macro, nil-default-identical); practice.lua untouched (registry complete). Pins in tests/paladin_state.lua (owned). Harness + luacheck + /tmp mutations.
- **Next step:** wow-ui-source branch verification, then implement.

## 2026-10-19 — DONE: paladin practice + designer fully built, pinned, green
- **Built:** seal/success detach + force-show (paladin.lua); seal_icons + success_text descriptors (designmode.lua); top-level Practice page + 5 live widgets (option_tables.lua); start seeding + AW macro (practice_ui.lua). practice.lua untouched (registry complete). Paladin options section byte-intact (diff-verified).
- **Verified:** paladin_state 520/520; probe 22/22 (caught queue-persist pre-land, fixed); 5/5 mutations killed on /tmp copies, restored green; harness 38/3 (designmode count = my descriptors, flagged; SODOPT shaman + wiring dead-hooks = sibling crossfire, zero paladin findings); luacheck floor 2/0 held (my files 0); branch cites Era/TBC/Forever; line endings preserved.
- **Reconcile owed (orchestrator):** designmode_state count pins 9→11 / 10→12 + by_key pins for the 2 new elements. Filed: rotation/timeline options, effects chip, keybind persistence, overlays (reasons in bench report).
- **Artifacts:** bench/paladin_practice_designer_2026-10-19.md (reconcile table + evidence).
- **Next step:** orchestrator validates + reconciles pins; in-client test session per standing rules.

## 2026-10-19 — [signal:done] paladin practice runs end-to-end, paladin elements designable
- Designer + Practice page + macro/seeding live, pins green, harness/luacheck/mutations held. Signal: desks/paladin-practice-designer/.signals/2026-10-19T120000Z.json.
