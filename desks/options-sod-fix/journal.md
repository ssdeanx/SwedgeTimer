# options-sod-fix — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Diagnose + fix the two SoD options reports from a shaman player: (1) no Practice section in options, (2) Design Mode page looks empty.
- **Scope:** option_tables.lua (visibility/routing fix only) + tests/options_load_state.lua (pins only). Read-only: designmode.lua, practice_ui.lua, practice.lua, class files, TOCs, hud.lua.
- **Next step:** verify established facts in-lane (practice_* at option_tables.lua:2126+ inside PALADIN func; design_mode group at :258 order 1.45), check practice_ui consumers per class, check designmode load/registration/SoD-nil guards, then fix or FILE.

## 2026-10-19 — SoD shaman reports diagnosed + fixed + pinned
- **Worked on:** (1) Practice: verified paladin-only scoping explains the report — practice_* widgets live in ST.class_opts_funcs.PALADIN (option_tables.lua:2126+), practice_ui.init only from ST.PALADIN.post_init, shaman documents no-practice-branch (:3282), shaman_weave scenario has zero practice_ui consumers — so no widget owed; filed per-class spec (consumer + shape) instead. (2) Design Mode: verified all 7 TOCs load design.lua before designmode.lua, group unconditional (8 widgets), all gets nil-safe on fresh shaman db (probe /tmp/opencode/probe_design.lua); found + fixed one real throw — dynamic-name design_toggle on hollow st.designmode (option_tables.lua:280/288 pre-fix) — with callable guards. Pins in tests/options_load_state.lua §15 (SODOPT, 31 sites).
- **Current state:** option_tables.lua + options_load_state.lua edited only. options_load_state 1664/0, full harness 38/0, luacheck floor held (repo 2/0, scope 0/0). Mutations M1/M2/M3 on /tmp/opencode/mut_sod kill (2/1/2 FAILs), copies restored cmp-clean. Bench: bench/options_sod_fix_2026-10-19.md (fix + FILE-S1 practice spec + FILE-S2 design residual). Dead end recorded: hollow state unreachable via TOC/order (design.lua pure); empty-page residual needs in-client evidence (filed, not guessed).
- **Next step:** orchestrator validation (in-client SoD shaman check: Design Mode page renders, /st design overlays; confirm FILE-S1/S2 routing).

## 2026-10-19 — [signal:done] options-sod-fix complete
- Practice scoping verified + filed with consumer/shape; design_toggle hardened + pinned; harness 38/0 green. Artifacts on bench. Awaiting orchestrator/in-client validation.
