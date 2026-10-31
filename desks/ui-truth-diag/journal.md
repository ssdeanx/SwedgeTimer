# ui-truth-diag — Journal

## 2026-10-28 — Desk opened
- **Purpose:** close the two "the UI lies / the diagnostics cannot see" findings from the
  independent publish audit (`bench/publish_audit_2026-10-28.md`, NOT READY):
  **E1** — the offhand Width slider is inert (`option_tables.lua:7203-7239` writes
  `offhand.bar_width`; `bars.lua:309-310` always overrides it from the mainhand); and
  **P4** — `/st diag` cannot see the failures that matter (no power-bar line, no
  activity-gate/receipt fields, no reason for `shown=no`, no quarantine site names).
- **Scope:** `option_tables.lua`, `diag.lua`, `main.lua`, `power_bar.lua`,
  `tests/options_load_state.lua`, `tests/diag_state.lua`. Nothing else. Version stays
  2.1.3; no git; no docs; no TOC/Libs edits; line endings LF and preserved.
- **Brief:** `bench/briefs/brief_ui-truth-diag_2026-10-28.md`.
- **Priors read:** central ledger `desks/journal.md` (NOT READY holds, the VOID of the
  stale "wave complete" block), `bench/lessons.md`, the audit §C2a/§E1/§P4, the
  layout-finish report §3 (the Height lock pattern this lane mirrors) and the
  bars-decouple report §1 (the activity gate + receipt contract).
- **Next step:** read every file before editing; E1 first (options truth), then P4
  (diag surface), then the pins and the gate.

## 2026-10-28 — E1 + P4 closed; gate green

- **Worked on:** E1 (offhand Width widget) in `option_tables.lua`; P4 (`/st diag` power line,
  per-hand gate/receipt/hidden-reason fields, quarantine site names) across `diag.lua`,
  `main.lua`, `power_bar.lua`; tests re-cut/extended in `tests/diag_state.lua` and
  `tests/options_load_state.lua`. Report: `bench/ui_truth_diag_2026-10-28.md`.
- **E1:** Width now shows the mainhand's width, is locked for the offhand only, its description
  says it follows the mainhand (hunter-stack sentence kept), and any write is routed to the
  mainhand key. Sibling offhand size controls audited: Height already locked (layout-finish),
  Scale/x/y/point functional, deadzone width derives from the effective width, no Appearance
  per-hand width exists. Nothing else in the options tree was inert.
- **P4:** one always-on `power` line (`ready/anchor/anchor_shown/shown/width/height/type/token/
  value/fraction/why`) fed by a new read-only `pb.resolve` receipt (`pb.last_state`, written
  only by `pb.update`); bar lines gained `why/gate/active/win/left/src` with the reason recorded
  where the visibility decision hides the bar and the receipt source recorded by
  `note_hand_activity`; one `quarantine` line naming every counted guard site (`[q]` marker,
  counts, sorted, capped at 8 with `+N more sites`). Verbose worst case 85 ≤ MAX_LINES 88.
- **Current state:** gate `bash tests/run.sh` **54 steps / 0 failed**; luacheck **2 warnings /
  0 errors in 97 files**; `tests/diag_state.lua` 389 checks, `tests/options_load_state.lua`
  3821, `tests/power_bar_state.lua` 190 (untouched), `tests/bars_state.lua` 1249 (untouched).
  20/20 mutation proofs killed (in-memory substitution harness; /tmp copies are being purged by
  another actor mid-wave). Version still 2.1.3; six files changed, all in scope; LF preserved.
- **Next step:** the operator's in-client pass on U1-U6 in the report §6 — especially the
  locked Width rendering, the power line's numbers vs the drawn bar, the `why=` tokens against
  each real hide, and the longer bar lines' chat readability. Two follow-ups belong to other
  owners: a behavioral `hide_reason` pin in `tests/bars_state.lua`, and (if the other lane's
  hunter driver frame returns) a re-cut of its `HUNTER extra_frames = 6` pin at
  `tests/bars_state.lua:992`.
