# docs-release — Journal

## 2026-10-28 — Desk opened
- **Purpose:** the release-notes desk: turn the wave's lane reports and the independent publish audit into honest, user-facing release notes (`CHANGELOG.md` + `README.md`) — prose only, no version bump, no in-client claims.
- **Scope:** `CHANGELOG.md` and `README.md` at the repo root; every wave that lands a user-visible change. Reads `bench/` reports and `bench/publish_audit_2026-10-28.md` as its evidence base. Does not touch code, TOCs, tests, other desks' files or the central ledger.
- **Next step:** session 2026-10-28 06:35 — write the 2026-10-28 wave notes into the existing `## [2.1.3]` section (version stays 2.1.3).

## 2026-10-28 — 2026-10-28 wave release notes written (2.1.3, no bump)
- **Worked on:** read the brief, `bench/publish_audit_2026-10-28.md` (SUPERSEDING, §P5-3 first) and the
  eight lane reports, then extended the existing `## [2.1.3]` section: CHANGELOG Added +2 (Melee pair
  height, `/st diag`), Changed +3 and 1 rewritten (activity gate, forced ranged placement, offhand sizing;
  the generic shot→melee-reset guard), Fixed +4 (hunter queue tint, Era `CR_HASTE_SPELL` crash,
  backdrop migration actually running, hunter visual set under a hidden ranged bar), Hardening +2 and an
  offline-only disclaimer. README: rewritten power-bar paragraph (offhand ROW ownership), new
  activity/ranged-placement paragraph, `/st diag` line. Corrected the stale "offhand when used"
  power-bar sentence (§P5-3). No in-client claim anywhere; no version bump.
- **Current state:** gate green before and after — 54 steps / 0 failed, luacheck 2/0 in 97 files.
  CHANGELOG 1222 lines, all CRLF; README 147 lines, all LF; version 2.1.3 untouched (7 TOCs + main.lua).
  Report at `bench/docs_release_2026-10-28.md` (evidence map + excluded claims + line-950 pinned
  passage note). Two audit MUST-NOTs (HU-37, E1) were overtaken by later lanes — flagged in report §6.
- **Next step:** operator in-client pass on TBC Anniversary + Classic Era (nothing in this wave is
  client-proven). If the reviewer wants the HU-37/E1 bullets out, each is one self-contained bullet —
  delete and re-run the gate. Still owed by the code owner: a test pin for the `LibGlobalCooldown.lua`
  Era fix (audit B1).

## 2026-10-28 — [signal:done] Release notes for the 2026-10-28 wave are on the tree
- `CHANGELOG.md` `## [2.1.3]` extended and the §P5-3 power-bar sentence corrected; `README.md` updated.
  Gate 54/0 before and after; signal at `desks/docs-release/.signals/2026-10-28T104823Z.json`.
