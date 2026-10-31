# publish-audit — Journal

## 2026-10-28 — Desk opened (dispatch: bench/briefs/brief_publish-audit_2026-10-28.md)
- **Purpose:** independent read-only verifier for the 2.1.3 release candidate.
- **Write scope:** bench/publish_audit_2026-10-28.md, desks/publish-audit/journal.md, signal. No product code/tests/TOCs/configs.
- **Next step:** run gate + checks A-G, file report, emit signal.

## 2026-10-28 — Reconcile (complete)
- Gate: `bash tests/run.sh` 54/0, twice, order-stable. luacheck 2 warnings / 0 errors.
- Report filed: bench/publish_audit_2026-10-28.md (sections A-G, verdict READY TO PUBLISH PENDING IN-CLIENT TEST).
- Verdict: READY TO PUBLISH PENDING IN-CLIENT TEST. Blocking list: operator in-client pass (section G), HU-35/37/38 rulings owed, latent AceDB trap reads (LOW), diag gaps (MED).

## 2026-10-28 05:52 EDT (09:52Z) — Superseding audit of the settled 2.1.3 tree (read-only) — verdict NOT READY
- **Worked on:** re-ran A-G + P1-P5 against the 05:21:08Z-settled tree (baseline 09:30:01Z, final
  09:48:37Z, zero drift; gate 54/0 twice; luacheck 2/0 in 97 files; focused suites 1249/1313/286/183/294/1104 checks).
  Appended a SUPERSEDING AUDIT section to `bench/publish_audit_2026-10-28.md` (the 05:09 report is now
  history only: it audited a mid-flight tree, cited a since-fixed get_class_table, claimed docs were updated, omitted
  latent-trap-hardening/paladin-sound). Verified every lane's closure hash, both migration idempotence pin sets,
  the false-trail ranged-forced VOID, HU-35/36 resolved and HU-37/38 open.
- **Findings:** no code BLOCKER in the six supported classes. Held by: E1 offhand Width slider inert (MED, user-visible lie);
  P5-3 release notes unwritten + stale power-bar sentence (MED); HU-37/HU-38 open rulings (E2/E3 MED); no in-client proof;
  B2/B3 stale "publish-audit DONE" report + journal block to void. Also: P1-2 options surface raises for Retail
  MONK/DEMONHUNTER/EVOKER (class token outside the ten defaults; MED, not classic-line); E6/E7 latch ordering (LOW);
  C2a/P4-1 diag gaps (quarantine sites, activity fields, power-bar line) (MED); B1 LibGlobalCooldown fix outside every lane (LOW).
- **Current state:** report + journal + signal on disk; no product/test/TOC/config touched by this desk.
- **Next step:** orchestrator voids the stale report/ledger block, locks the offhand Width widget (or routes it to the
  mainhand key), writes CHANGELOG/README per §P5-3, then the operator runs §G on TBC Anniversary + Classic Era.
