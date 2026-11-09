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

## 2026-11-06 — 2.1.8 release notes written (CHANGELOG + README)
- **Worked on:** read the Lead dispatch, `bench/forever_display_audit_2026-11-06.md`
  (A-1/A-2/A-3/A-4, B-1/B-5/B-6/B-7, §8), the three fix reports
  (`bench/display_fix_2026-11-06.md`, `bench/powerbar_secret_2026-11-06.md`,
  `bench/bars_perf_fix_2026-11-06.md`) and the three fix-desk journals, then wrote a new
  `## [2.1.8]` section above `## [2.1.7]` (offline-only/UNCONFIRMED verification status,
  7 Fixed bullets, Version 2.1.8) and updated README: What's New v2.1.8, rewritten callout,
  new "WoW Forever Display, Range & Power Fixes (v2.1.8)" bullets, Release Highlights
  relabelled `(v2.1.7)`, footer disclaimer tightened.
- **Correction (Lead, before close):** my first range-bar parenthetical said the unknown face
  covers "no target"; the fix report §B-5 is target-present + attackable + distance-unknown
  only (no target / non-attackable still hides). Fixed in both files and the callout; no other
  wording changed.
- **Current state:** docs describe the 2.1.8 wave with no in-client claim; `toc_check`
  **1104 checks / 0 failures** (the `- **The per-class sets.**` passage proven byte-identical
  to HEAD; it moved 1223 → 1244 only); README/CHANGELOG LF (0 CR each); version 2.1.8 in the
  7 TOCs + `main.lua:5` untouched by this desk. Report `bench/docs_release_2026-11-06.md`;
  README sha256 `976000eb…98d589`, CHANGELOG `f93d78f6…4c91936`; scoped diff 2 files,
  +32/−4; no git commit.
- **Next step:** operator in-client Forever pass closes every UNCONFIRMED item; Lead/operator
  reconciles the wave and commits. Remaining README `2.1.7` strings are only the two
  historical subsection labels (`:49`, `:70`).

## 2026-11-06 — [signal:done] 2.1.8 notes are on the tree
- CHANGELOG `## [2.1.8]` + README v2.1.8 display/power/bar-text notes written and verified;
  Lead's range-bar correction applied and `toc_check` re-run 1104/0. Signal at
  `desks/docs-release/.signals/2026-11-06T195226Z.json`.


## 2026-11-06 — 2.1.8 notes extended: secret-value hardening block
- **Worked on:** read the five secret-wave reports (`bench/secret_api_matrix_2026-11-06.md`,
  `bench/secret_consumers_audit_2026-11-06.md`, `bench/secret_core_fix_2026-11-06.md`,
  `bench/secret_guide_fix_2026-11-06.md`, `bench/secret_hud_fix_2026-11-06.md`) plus the
  central ledger's final secret-wave reconcile; added `### Hardening` inside `## [2.1.8]`
  (5 sub-bullets: unknown-not-guessed gathers incl. the latent paladin crash, ToT
  `SetAlphaFromBoolean` pass-through, HUD trinket grey-unknown face, hunter
  identity/aura/creature-type guards, compat hardening) and a new README
  `### 🔒 Secret-Value Hardening (WoW Forever, v2.1.8)` block plus a callout clause. The
  verification-status line now carries the final gate (57/0, luacheck 2/0) and explicitly
  keeps in-client secret triggers/rendering UNCONFIRMED.
- **Current state:** total docs diff vs HEAD — CHANGELOG +30, README +19/−4 (this pass
  +9 and +8 lines). `toc_check` 1104/0 exit 0; pinned passage byte-identical to HEAD
  (2530 chars); README `2.1.7` only the historical labels (`:57`, `:78`); LF preserved
  (0 CR); version 2.1.8 untouched; no git commit.
- **Next step:** operator in-client Forever pass (all UNCONFIRMED items incl. the secret
  triggers/rendering); Lead/operator reconciles and commits.

## 2026-11-06 — [signal:done] Secret-value hardening block added to 2.1.8 notes
- CHANGELOG `### Hardening` + README `### 🔒 Secret-Value Hardening (WoW Forever, v2.1.8)`;
  `toc_check` 1104/0; signal at `desks/docs-release/.signals/2026-11-06T222420Z.json`.
