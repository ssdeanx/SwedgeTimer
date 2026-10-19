# Brief: oracle-audit — full-round strategic audit (standing rule)
Date: 2026-10-17. Orchestrator-issued. Standing rule: audit after each section. This section = everything since the last oracle pass: build-out round 1 (10 lanes) + competitor-scan + shaman-weave + options (27 toggles) + enterprise-grade wave (5) + reconcile + 120105-matrix + options-followup + hud-reflow.

## Read first (all verified on disk)
desks/oracle/journal.md · desks/journal.md (full lane table + decisions) · CAIRN.md · AGENTS.md (conventions, cross-engine rules, wire-not-strip) · hands-up.md (HU-1..HU-4) · bench/lessons.md · bench/verify_bank.md · bench/discover_features.md · bench/competitor_scan_2026-10-17.md · every bench/buildout_*_2026-10-17.md report (11 + weave + options + 5 grade + reconcile + followup + reflow — read at least their changes/evidence/UNCONFIRMED/gaps/out-of-scope sections).

## Scope — READ-ONLY on code
Write ONLY: bench/oracle_audit_2026-10-17.md + desks/oracle/journal.md entry + signal JSON. No code edits, no git, no lint changes. You may run `bash tests/run.sh` and `luacheck` read-only to confirm stated evidence (do not modify the tree).

## Task — adversarial audit for merge/test readiness
Judge as if the owner loads this in-client tomorrow. Probe: cross-client gating (any `st.is_mainline`-alone gates? Era/UNKNOWN leaks? secret-value exposure on Mainline-code paths?), combat-taint safety (show/hide, strata/parent changes, reflow deferral), contract integrity between parallel lanes (C2 aura-scan semantics vs H2/P3 consumers; pips `ST:new_pips` signature vs druid wiring; design-target registry vs frames that exist; option keys vs consumer reads), performance (per-tick allocation, aura poll cost), test-honesty (do the suites pin behavior or just counts? any weakened pins vs the pre-round baselines?), and doc truth (AGENTS.md/TESTING.md/README vs the tree).
Rank every finding: severity (BLOCKER / RISK / NIT), file:line, evidence, fix direction. Separate "must fix before in-client" from "defer with rationale". Close with an explicit readiness verdict: READY / READY-WITH-FIXES / NOT-READY.

## Deliverables
bench/oracle_audit_2026-10-17.md (ranked findings + verdict) · desks/oracle/journal.md entry · signal JSON (done|blocked). Final reply ≤10 lines: verdict + count of BLOCKERs/RISKs. NEVER run git.
