# Brief — ui-truth-diag (2026-10-28)

Desk: `ui-truth-diag`. Two findings from the independent publish audit
(`bench/publish_audit_2026-10-28.md`, SUPERSEDING AUDIT) must be closed before this build can
be called release-ready. Both are "the UI tells a lie" / "the diagnostics cannot see" class
defects — exactly what the operator is holding the release for.

## E1 (MED) — the offhand Width slider is inert

`option_tables.lua:7203-7239` writes `offhand.bar_width`, but `bars.lua:309-310` always
overrides the offhand's width from the mainhand's on every layout pass. The Height control
was locked by `layout-finish`; **Width was not**. Operator order in force: "off hand should
always be same width as main hand." A control that silently does nothing is not acceptable in
a publishable build.

Required: make the options truthful. Either lock the offhand Width widget the way Height is
locked (showing the effective mainhand width, disabled, with a short description saying it
follows the mainhand) or route it to the mainhand key. Do not leave a control that accepts
input and ignores it. Same treatment for any sibling offhand size control that is inert.

## P4 (MED) — `/st diag` still cannot see the failures that matter

The audit's list: no power-bar line at all; no activity-gate/receipt fields (an expected bar
hidden by the gate is indistinguishable from a bar that is switched off); no reason given for
`shown=no`; quarantine site names absent (only the total `bar_hook_errors`).

Required, print-only and nil-safe like the rest of the report:
- **A power line**: anchor hand, shown/hidden, width/height, fraction, power type + value/max
  (or `unknown` when the read degrades).
- **Bar lines**: add the activity/receipt state per hand — whether the activity gate is open,
  the window remaining, and the receipt source — plus a short reason when `shown=no`.
- **A quarantine line**: each guarded site name with its throw count (not just the total).

Update `tests/diag_state.lua` for the new lines/caps and `tests/options_load_state.lua` for
the truthful widget.

## Write scope

`option_tables.lua`, `diag.lua`, `main.lua`, `power_bar.lua`, `tests/options_load_state.lua`,
`tests/diag_state.lua`. Nothing else: no `config.lua`, no `bars.lua`, no `classes/*`, no
TOCs, no docs, no `Libs/`, no `.luacheckrc`, no `tests/run.sh`.

## Rules

- Load and follow the lane skills first: `bench-read`, `desk-open` (desk `ui-truth-diag`),
  `desk-journal`, finish with `signal-write`.
- Read every file you edit before editing it.
- No git. Preserve line endings. **Version stays 2.1.3.**
- `bash tests/run.sh` must stay green (54 steps / 0 failed; luacheck 2 warnings / 0 errors in
  97 files). List every pin you re-cut and why.
- Report to `bench/ui_truth_diag_2026-10-28.md`; journal at `desks/ui-truth-diag/`.
- State what needs a live client (the widget rendering and the new diag line readability).
