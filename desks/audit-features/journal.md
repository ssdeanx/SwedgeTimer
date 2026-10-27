# Audit Features — Journal

## 2026-10-25 — Desk opened
- **Worked on:** reading AGENTS.md / CAIRN.md / workshop.md / bench/lessons.md and the
  central ledger tail before any scan; scope = deep behaviour + reliability +
  enhancement audit of classes/*.lua, practice*.lua, the guide engines/UI, twist/weave,
  design/options/config. Read-only: no product code edits.
- **Current state:** desk open, artifact target `bench/audit_features_2026-10-25.md`
  (new file; verified absent at open).
- **Next step:** inventory promised systems per class, then isolation / practice /
  per-client / performance / reliability sweeps.

## 2026-10-25 — Deep feature audit landed
- **Worked on:** six-class behaviour inventory (guide/HUD/practice/options), class-isolation
  sweep (wiring_check §10 + the `player_class` routes §10 cannot see), practice-integrity
  read of the scoring/XP/achievement path, per-client spell-id sweep (verified the Era
  `56641` probe against `/home/sam/wow.export`), per-tick cost census (hunter aura walks),
  reliability sweep (pcall/guard, init order, latches). Ran focused suites only, never
  `tests/run.sh`.
- **Current state:** report at `bench/audit_features_2026-10-25.md` (new file). Top findings:
  class_activation is half-wired (HIGH), Era/SoD range probe uses a spell absent from the
  1.15.9 client (HIGH), practice grading is answer-revealed + re-clickable so stats/
  achievements inflate (HIGH), hunter gather does 3-6 full aura walks per 50 ms (MEDIUM),
  practice pcalls hide a permanently broken class step (MEDIUM). Tree was moving during the
  audit (practice/hunter/main edits 12:38-12:57); `practice_ui_state` was red mid-wave and
  green (2608/0) at the final snapshot; smoke 232/0, wiring 873/0/3 accepted.
- **Next step:** operator triage of F1 (activation ruling: practice-only label vs route all
  hooks through `active_class`) and F2/F3; re-run `practice_ui_state` + `hunter_state` after
  the in-flight wave settles; in-client legs needed for every fix (none verified here).

## 2026-10-25 — [signal:done] Deep feature audit delivered
- Bench artifact: `bench/audit_features_2026-10-25.md`.
- 12 ranked fixes + 12 ranked enhancements; UNVERIFIED list explicit.
