# release-217 — Journal

## 2026-11-05 — Desk opened
- **Purpose:** write-lane for the 2.1.6 → 2.1.7 version fields only, while the 2.1.7 fixes
  are still landing in parallel lanes.
- **Scope (exact):** `## Version` line 6 of the seven live TOCs (`SwedgeTimer`,
  `SwedgeTimer_Vanilla`, `SwedgeTimer_TBC`, `SwedgeTimer_Wrath`, `SwedgeTimer_Mainline`,
  `SwedgeTimer_Cata`, `SwedgeTimer_Mists`), `main.lua:5`, `README.md:37` heading,
  `README.md:40` body sentence, plus this journal and the done signal.
- **Explicitly NOT in scope:** `CHANGELOG.md` (no entry yet — the fixes are mid-flight),
  `Libs/LibClassicSwingTimerAPI/*.toc`, `docs/swedge/**`, any `## Interface` value, any
  bench/desk historical reference, any `classes/*.lua`, `compat.lua`, `hud.lua`,
  `nextaction_ui.lua`, `forever_guide.lua`, `tests/`, all other files.
- **Priors read:** `desks/journal.md` (central ledger), `bench/lessons.md`,
  `desks/version-bump/journal.md` and `desks/version-docs/journal.md` (the two prior
  version-field lanes — same 8-field core, plus README edits in version-docs).
- **Tree state at open:** `git status --porcelain` → empty (clean tree, no in-flight edits
  visible on disk at that moment). All nine target files read **LF only** at open
  (TOCs 78/78/78/78/77/77/77 lines, `main.lua` 3349, `README.md` 230); no CRLF anywhere.

## 2026-11-05 — [signal:done] 2.1.6 → 2.1.7 fields bumped (10 lines / 9 files)
- **Worked on:** nine in-place line edits, one occurrence each, no surrounding text touched.
- **Exact changes made:**
  - `SwedgeTimer.toc:6` — `## Version: "2.1.6"` → `## Version: "2.1.7"`
  - `SwedgeTimer_Vanilla.toc:6` — same
  - `SwedgeTimer_TBC.toc:6` — same
  - `SwedgeTimer_Wrath.toc:6` — same
  - `SwedgeTimer_Mainline.toc:6` — same
  - `SwedgeTimer_Cata.toc:6` — same
  - `SwedgeTimer_Mists.toc:6` — same
  - `main.lua:5` — `local version = "2.1.6"` → `local version = "2.1.7"` (`ST.addon_version`
    at `main.lua:10` derives from it; the `main.lua:8-9` "keep in sync" comment stays true)
  - `README.md:37` — `## 🚀 What's New in v2.1.6` → `## 🚀 What's New in v2.1.7`
  - `README.md:40` — `SwedgeTimer v2.1.6 brings …` → `SwedgeTimer v2.1.7 brings …`
    (rest of the sentence byte-identical)
- **Line endings:** re-checked after the edits — all nine files still LF only (zero `\r`
  bytes). The TOCs are LF in this tree today, not CRLF; preserved as found, not converted.
- **Deliberately unchanged:** `CHANGELOG.md:3` `## [2.1.6]` (history), the six
  `Libs/LibClassicSwingTimerAPI/*.toc` `## Version: 2.1.5` (vendored, untouched), every
  `## Interface` header (toc_check's exact-value pins still pass), `docs/swedge/**`.

## Validation evidence
- **`lua5.1 tests/toc_check.lua` → exit 0, `1104 checks, 0 failures`.** Baseline before the
  edits was also `1104 checks, 0 failures`, so the count is unchanged and no check flipped.
  This is the run that proves the `## Interface` pins, path casing, load order and the
  local-count ceiling all survived.
- **Live-version grep:** `grep -n '2\.1\.6'` across the seven TOCs + `main.lua` → **no hits**
  (exit 1). `README.md` top section (lines 30–45) → **no hits**; only the two `v2.1.7`
  strings. The only surviving `2.1.6` in the repo docs is the historical
  `CHANGELOG.md:3` `## [2.1.6]` header, which is meant to stay.
- **Independent consistency check (read-only, throwaway script, not committed):** parsed
  line 6 of all seven TOCs, line 5 of `main.lua`, and both README strings; all ten values
  agreed on `2.1.7` → `consistency_fail=0`. Script deleted afterwards, no file added.
- **`git diff --stat` → 9 files, 10 insertions(+), 10 deletions(-)**, exactly:
  `README.md 4 ++--` and `1 +-` each for the seven TOCs + `main.lua`. `git diff --numstat`
  agrees (2/2 for README, 1/1 for each other). `git diff --name-only` lists only those nine
  paths. `git diff --name-only -- CHANGELOG.md Libs docs tests classes compat.lua hud.lua
  nextaction_ui.lua forever_guide.lua` → **0 paths**. `git diff -U0 | grep '^[-+][^-+]'`
  shows exactly the ten paired lines and nothing else.
- **Untracked:** `desks/release-217/` (this journal + `.signals/2026-11-05T043530Z.json`)
  is the only new path, per `git status --porcelain`.

## Gaps / not verified (stated, not papered over)
- **No CHANGELOG entry was written** — out of scope by dispatch order (the fixes are still
  landing). Reader: the 2.1.7 section is owed once the wave reconciles.
- **No automated regression pin covers version-field sync.** `tests/toc_check.lua` has no
  `## Version` assertion (grep for `version` in that file → zero matches), so a future
  partial bump would not fail the harness. Evidence here is the one-off grep + consistency
  script above, not a durable test. Adding a pin would be a `tests/` edit, which this lane
  may not make; filed as the follow-up below.
- **In-client version display UNVERIFIED.** The TOC `## Version` and `main.lua` `version`
  are proven equal on disk only; the addon-list string was not observed in a running client.
- **`desks/version-bump/journal.md` says the field is "line 5 of all 7 TOCs".** In today's
  tree it is line 6 (a header line was added after 2026-10-19). The dispatch's line-6
  instruction matches the tree; the older note is historical, not edited.

## Next step
- Orchestrator reconcile: confirm the nine files, then write the `## [2.1.7]` CHANGELOG entry
  once the parallel fix lanes land. Optional follow-up outside this lane: a `toc_check.lua`
  assertion that all seven TOCs + `main.lua` carry the same version string.
