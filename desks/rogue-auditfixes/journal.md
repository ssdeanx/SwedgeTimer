# rogue-auditfixes desk journal

Format: worked on / current state / next step (desk-journal).

## 2026-10-19 — lane start

- Worked on: bench-read (desks/journal.md, bench/rogue_erroraudit_2026-10-19.md
  whole file, bench/lessons.md); file checks (practice.lua CRLF, compat.lua LF,
  tests LF); verified all fix sites on disk (practice.lua:2505-2623,
  compat.lua:1105-1114, rogue_guide_state pins, secret_guard item-count block).
- Current state: F1/F2/F4/F5/F6 edits not yet applied. F3/F7/F8 confirmed
  NO ACTION per brief + journal reconcile decisions. Desk open at
  desks/rogue-auditfixes/.
- Next step: apply F1 guards + 2 pins, F2 guard + pin, F4/F5/F6 pins; run
  harness + luacheck; mutation proofs on /tmp/opencode copies; signal done.

## 2026-10-19 — lane done

- Worked on: F1 guards (practice.lua marker/interval/latency/start/window/ideal
  NaN paths) + 2 pins; F2 type guard (compat.lua GetItemCount) + 1 pin;
  F4 (2 cell pins), F5 (3 rule-order pins), F6 (BOGUS pin, no engine change).
  Harness 37/0 + luacheck 2/0; 8/8 mutations fail-when-stripped on
  /tmp/opencode/rogue-auditfixes-mut/tree, tree verified IDENTICAL after
  restore. Signal: desks/rogue-auditfixes/.signals/2026-10-19T115728Z.json.
- Current state: F1/F2/F4/F5/F6 CLOSED with pins + mutations; F3/F7/F8
  recorded NO ACTION with rationale. Endings preserved (practice.lua CRLF,
  compat.lua LF). No other files touched.
- Next step: none — lane complete, awaiting orchestrator reconcile.
