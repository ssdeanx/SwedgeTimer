# perclient-gaps — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Close G1–G8 in bench/perclient_api_audit_2026-10-19.md: confirm each gap against
  wow-ui-source branch source (branch:file:line), mark CONFIRMED (with fix direction) or
  UNVERIFIABLE (with what's missing).
- **Scope:** READ ONLY except bench gap dispositions. No addon/test edits, no git checkout/commit,
  no weakaura bench files.
- **Next step:** Verify claims via `git show <branch>:<path>` (checked-out branch untouched),
  append dispositions to the bench file, signal done.

## 2026-10-19 — Gaps dispositioned, bench appended
- **Worked on:** bench-read (audit file found truncated at line 52; G-list recovered only via
  compat-audit-fixes journal quote of 3 compat gaps); git-show verification of every surviving §1
  claim + all 3 compat gaps on classic_era/classic_anniversary/classic_titan/origin/forever/live
  (checked-out branch untouched); appended §2 dispositions to bench/perclient_api_audit_2026-10-19.md.
- **Current state:** 3 compat gaps CONFIRMED (fixes already landed compat.lua:184-204,739-747,1013 —
  no new build owed); truth-table values CONFIRMED with 2 citation refinements (variant-file client
  identity; Cata-variant bare globals on forever/live); UnitAura row + 5 gap numbers UNVERIFIABLE
  (definitions absent — dispatch objectives of ses_eaabf8ba6ffe5OcD3QHmpLXS9S needed); §0 RED stale.
  Zero addon/test edits; LF endings kept (append-only).
- **Next step:** orchestrator validates + rules: supply the 5 missing gap definitions or accept this
  as closure. Validation owner: orchestrator.
- [signal:done] 2026-10-19 — dispositions on bench; 3/8 CONFIRMED, 5/8 UNVERIFIABLE (missing source text), validation owned by orchestrator.
