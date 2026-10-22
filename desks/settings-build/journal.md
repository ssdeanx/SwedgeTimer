# settings-build — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build the settings-audit spec (bench/settings_audit_2026-10-19.md): maul desc, order collisions, copy cleanups, per-class alignment. Filed decisions (HS/AM HUD, hamstring, guide-only HUD) stay filed.
- **Scope:** ONLY option_tables.lua (copy/order/widget text), config_presets.lua (only if audit specs a default), tests/options_load_state.lua (pins). No class/guide/engine/compat/bars/hud/practice/main/diag/contract/run/TOC/README/docs/version edits. No new widgets beyond audit spec. No git.
- **Next step:** implement audit rows, harness + luacheck + mutation proofs on /tmp/opencode copies.

## 2026-10-19 — Audit spec built (done)
- **Worked on:** Built bench/settings_audit_2026-10-19.md in option_tables.lua (copy/order only) + tests/options_load_state.lua (§4c scope fix, RIPCP 7.96, new §14 audit pins). D-C1 maul→Maul, D-C2 casing, X1/X2/X3/X5 qualified, X4 per-class format values, P-C1..C7/P-O1..O3 (gates, 3.984/3.46/3.47), W-C2..C5/W-O1 band 3.10-3.28/W-O2 4.131, H-C1..C6/H-O1 7.101/H-O2 7.5x/H-O3 desc, S-C1..C5/S-O1 2.31+2.65/S-O2 3.101, D-O1 6/6.5/7/7.95x (7.95x not 7.5x to dodge 7.5/7.6 collisions) + D-O2 spacers deleted, R-C1..C3/C5/R-O1 2.03 (R-C4 kept). Filed stay filed: P-M2/W-M1/H-M2/R-M1 absent-pinned. No config_presets change (no default spec'd).
- **Current state:** Done. Harness 38/0, luacheck 2/0 floor, 3/3 mutations kill on /tmp/opencode copies (M1 maul revert, M2 warrior 3.10 collision, M3 lock revert); copies removed. Endings preserved, no trailing WS.
- **Next step:** Orchestrator validates (re-run harness, spot-check hunks); in-client session owns D-O1/W-O1/H-C1/X4 visuals (all UNCONFIRMED in-client).
- [signal:done] settings-audit built with pins, filed rows absent-pinned
