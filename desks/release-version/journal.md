# release-version — Journal

## 2026-11-06 — Desk opened (2.1.7 → 2.1.8, 8 fields only)
- **Purpose:** the ONLY writer of the version fields for the 2026-11-06 WoW Forever
  display/bars-perf wave. Operator-approved bump 2.1.7 → **2.1.8**.
- **Scope (exact, 8 fields / 8 files):** `## Version` line 6 of the seven live TOCs
  (`SwedgeTimer`, `SwedgeTimer_Vanilla`, `SwedgeTimer_TBC`, `SwedgeTimer_Wrath`,
  `SwedgeTimer_Mainline`, `SwedgeTimer_Cata`, `SwedgeTimer_Mists`) + `main.lua:5`
  `local version` (`ST.addon_version` at `main.lua:10` derives from it).
- **Explicitly NOT in scope:** `README.md`, `CHANGELOG.md`,
  `Libs/LibClassicSwingTimerAPI/*.toc`, `docs/swedge/**`, any `## Interface` value, any
  historical bench/desk reference, any other Lua file, tests. No commit (operator owns git).
- **Priors read:** `desks/journal.md` (central ledger — the 2026-11-06 dispatch entry names
  2.1.8 as the target and baseline 57/0), `desks/release-217/journal.md` (the prior bump
  desk, same 8-field core), `bench/lessons.md` (tail).
- **Tree state at open:** HEAD `7207f80` ("release v2.1.7"). `git status --porcelain` was
  NOT clean: `M desks/journal.md` (the orchestrator's own 38-line 2026-11-06 dispatch entry,
  mtime 14:01:42, predating this session) + untracked `.dsh-progress/` (harness-owned).
  No in-flight edits by any other lane on the eight target files. All eight files read
  **LF only** (CR=0) at open; line counts 78/78/78/78/77/77/77 TOCs, `main.lua` 3350.

## 2026-11-06 — [signal:done] 2.1.7 → 2.1.8 bumped (8 lines / 8 files)
- **Worked on:** eight in-place single-line edits, one unique occurrence per file, no
  surrounding text touched. Used the `edit` tool with exact-match replacement.
- **Exact changes made:**
  - `SwedgeTimer.toc:6` — `## Version: "2.1.7"` → `## Version: "2.1.8"`
  - `SwedgeTimer_Vanilla.toc:6` — same
  - `SwedgeTimer_TBC.toc:6` — same
  - `SwedgeTimer_Wrath.toc:6` — same
  - `SwedgeTimer_Mainline.toc:6` — same
  - `SwedgeTimer_Cata.toc:6` — same
  - `SwedgeTimer_Mists.toc:6` — same
  - `main.lua:5` — `local version = "2.1.7"` → `local version = "2.1.8"`
    (`main.lua:6` `-- local version = "2.0"` is a pre-existing comment, untouched;
    `main.lua:8-9` "keep in sync" comment stays true; `ST.addon_version` derives)
- **Line endings:** re-checked after the edits — all eight files still CR=0 (LF preserved
  as found, not converted). Line counts unchanged (78/78/78/78/77/77/77, `main.lua` 3350).
- **Deliberately unchanged:** `README.md` (3 live `2.1.7` strings at :37/:40/:63),
  `CHANGELOG.md` (3 live `2.1.7` strings at :3/:5/:49 — `## [2.1.7]` is history, the
  :49 bullet is the old bump's own record), `Libs/LibClassicSwingTimerAPI/*.toc`
  (vendored `## Version: 2.1.5`), every `## Interface` header, `docs/swedge/**`.

## Validation evidence
- **`grep -n '## Version'` on the seven TOCs → all seven read `2.1.8` at line 6**
  (SwedgeTimer, _Vanilla, _TBC, _Wrath, _Mainline, _Cata, _Mists).
- **`grep -n 'local version' main.lua` → `5:local version = "2.1.8"`** (line 6 is the
  pre-existing `"2.0"` comment). Unique version value across the eight files: `2.1.8`.
- **`grep -rn '2\.1\.7'` across the seven TOCs + `main.lua` → no hits (exit 1).**
- **`lua5.1 tests/toc_check.lua` → exit 0, `1104 checks, 0 failures`.** Baseline before the
  edits was also `1104 checks, 0 failures`, so the count is unchanged and no check flipped.
  (Verified `tests/toc_check.lua` contains **zero** `version` references — no pin exists to
  flip either way; the pass proves `## Interface` exact-value pins, path casing, load order
  and the local-count ceiling all survived.)
- **`git diff --stat -- <8 paths>` → exactly 8 files, 8 insertions(+), 8 deletions(-)**;
  `git diff --numstat -- <8 paths>` = 1/1 for each. `git diff -U0 -- <8 paths> |
  grep '^[-+][^-+]'` → exactly 16 lines = the 8 paired version lines and nothing else.
- **Scope proof:** `git diff --name-only -- README.md CHANGELOG.md Libs docs tests classes
  compat.lua bars.lua hud.lua power_bar.lua weave_range.lua hunter_ui.lua tests/run.sh`
  → **0 paths**.
- **Tree note (stated, not hidden):** unfiltered `git diff --stat` lists **9** files / 46
  insertions because `desks/journal.md` was already modified before this desk opened (the
  orchestrator's 38-line dispatch entry, mtime 14:01:42; this session started 14:06:23).
  It is not this lane's edit and was not touched. Excluding it, the lane's diff is exactly
  the required 8/8/8. Untracked `.dsh-progress/session-…/` is harness-owned.

## Gaps / not verified (stated, not papered over)
- **`README.md` and `CHANGELOG.md` still say 2.1.7.** My dispatch explicitly excludes them;
  the central ledger's 2026-11-06 entry says the version/docs desk owns README/CHANGELOG.
  So the docs bump for 2.1.8 is **owed by another lane / the Lead's call**, not done here.
- **No automated regression pin covers version-field sync.** `tests/toc_check.lua` has no
  `## Version` assertion (grep for `version` → 0 matches), so a future partial bump would
  not fail the harness. Evidence here is the one-off grep/diff proof, not a durable test;
  adding one would be a `tests/` edit, outside this lane's scope (same gap the
  `release-217` desk filed — still open).
- **In-client version display UNVERIFIED.** TOC `## Version` and `main.lua` `version` are
  proven equal on disk only; the addon-list string was not observed in a running client.
- **`desks/version-bump/journal.md` says the field is "line 5 of all 7 TOCs".** In today's
  tree it is line 6 (a header line was added after 2026-10-19); the dispatch's line-6
  instruction matches the tree. The older note is historical, not edited.

## Next step
- Lead/orchestrator: reconcile the 8 files (no commit — operator owns git), then have the
  docs owner bump `README.md` (:37/:40/:63) and add the `## [2.1.8]` CHANGELOG section once
  the parallel fix lanes land. Optional follow-up outside this lane: a `toc_check.lua`
  assertion that all seven TOCs + `main.lua` carry the same version string.

## 2026-11-06 — [signal:done] Restored 2.1.8 after rogue 2.2.0 overwrite (8 fields)
- **Incident (recorded by the orchestrator, `desks/journal.md:1912-1917`):** a rogue
  read-only desk — the resumed `perf-audit` turn — wrote **2.2.0** into the 7 TOCs +
  `main.lua:5` at 14:11, and also overwrote `bench/bars_perf_audit_2026-11-06.md` with a
  17-line stub. The operator-approved target is **2.1.8**. Corroborating history:
  `hands-up.md:55` (HU-21) records the operator ruling that no 2.2.0 bump/header is
  sanctioned; `desks/forever-audit/journal.md:48-52` observed the drift
  (2.1.7 → 2.1.8 → 2.2.0) and made no version claim; `desks/display-fix/journal.md:22-24`
  and `desks/bars-perf-fix/journal.md:11-13` explicitly disclaim the version fields.
- **Worked on:** eight in-place single-line edits, `2.2.0` → `2.1.8`, exact-match, one
  unique occurrence per file — the same 8 fields as the original bump, nothing else.
- **State at restore time:** all 8 fields read `2.2.0`; the fix desks' work was already in
  the tree (`main.lua` 3500 lines, +194/−44 vs HEAD; `bars.lua`, `hunter_ui.lua`,
  `compat.lua`, `power_bar.lua`, `swing_source.lua`, `weave_range.lua`, `utils.lua`,
  `diag.lua` + tests modified, mtimes 14:22-14:38). `README.md`/`CHANGELOG.md` were NOT
  touched by the rogue desk (still at HEAD).
- **Surgical proof:** recorded the pre-restore `main.lua` sha256
  `6af1de089e8da7bbe90ebf20ed3f2777f214ef9eb488feedfc390465f2d91d44`; after the restore,
  `sed '5s/"2\.1\.8"/"2.2.0"/' main.lua | sha256sum` reproduces that exact hash — so the
  restore changed **only line 5** of main.lua and every other byte (including the fix
  desks' 194 insertions / 44 deletions) is untouched. (The `/tmp` snapshot was cleaned
  mid-turn; the hash reconstruction is the stronger proof and is what is cited.)
- **Scope proof:** the 7 TOCs diff 1/1 each vs HEAD; `main.lua` still diffs +194/−44 vs
  HEAD (the fix desks' work, not mine). Only the 8 owned files have mtime 14:47:39; the
  fix-desk files keep their 14:22-14:38 mtimes. No other file written.

## Validation evidence (restore)
- `grep -n '## Version'` on the seven TOCs → **2.1.8 at line 6 in each**;
  `grep -n 'local version' main.lua` → **`5:local version = "2.1.8"`** (line 6 `"2.0"`
  comment untouched). Unique value across the 8 files: `2.1.8`.
- `grep -rn '2\.1\.7\|2\.2\.0'` across the 7 TOCs + `main.lua` → **no hits (exit 1)** —
  both the committed 2.1.7 and the rogue 2.2.0 are gone from the live fields.
- `lua5.1 tests/toc_check.lua` → **exit 0, `1104 checks, 0 failures`** (same count as the
  pre-restore green run; `toc_check.lua` itself is unmodified by any lane).
- **LF preserved:** CR=0 in all 8 files; line counts unchanged (78/78/78/78/77/77/77 TOCs,
  `main.lua` 3500 — the fix desks' line count, not mine).
- Version-line pairs across the 8 files: exactly **8 pairs (16 lines)**
  (`-## Version: "2.1.7"` / `+## Version: "2.1.8"` ×7, `-local version` / `+local version`
  ×1) — the scoped `-U0` diff for main.lua additionally carries the fix desks' hunks,
  which are theirs and were left intact.
- Live `2.2.0` remaining in the repo: only `hands-up.md:55` (the historical HU-21 ruling
  text, out of scope and correct as history). No live product file carries 2.2.0.

## Next step
- Lead: this restore is the final state of the 8 version fields (**2.1.8**). Fix desks' work
  is intact and untouched; no commit (operator owns git). Still owed by the docs owner:
  `README.md` (:37/:40/:63) and a `## [2.1.8]` CHANGELOG section — both still at 2.1.7/2.1.7
  history and explicitly outside this lane. Optional: the durable version-sync pin in
  `tests/toc_check.lua` (this incident is exactly the failure mode such a pin would catch).
