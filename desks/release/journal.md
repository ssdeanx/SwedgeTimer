# release — Journal

## 2026-10-17 — Desk opened
- **Purpose:** pre-publish pass — version bump 2.0.8 → 2.1.0 everywhere, CHANGELOG/README/TESTING accuracy vs the tree, publish checklist. CHANGELOG stays [Unreleased] until post-test publish.
- **Scope:** 7 tocs (Version lines), main.lua (version field), CHANGELOG.md, README.md, TESTING.md. Metadata + docs only, zero behavior change.
- **Next step:** execute bench/briefs/brief_release_2026-10-17.md.

## 2026-10-17 — Release pass executed (done)
- **Bump:** 2.0.8 → 2.1.0 in all 7 tocs (Version lines) + main.lua:5 (line-6 comment kept) + TESTING.md:33 diag example. Live `2.0.8` grep-zero; 4 remaining hits are intentional history (CHANGELOG [2.0.8] header, brief ×2, this journal's scope line).
- **README fixes:** `24 steps` → `35 steps` (3 spots); `/st` tooling row now lists practice/design/diag verbs.
- **CHANGELOG [Unreleased]:** spot-checked vs tree (lust 1..40, lust_supported, diag/enemy defaults, `not is_retail` gates, `(future)` copy) — accurate, untouched, header stays [Unreleased] until post-test publish.
- **Publish checklist:** toc_check green (in 35/0 run), TODO/FIXME zero, endings preserved (tocs/main/CHANGELOG CRLF; README/TESTING as before).
- **Validation:** `bash tests/run.sh` → 35 steps, 0 failed; luacheck 2 warnings / 0 errors (standing 2).
- **Report:** bench/buildout_release_2026-10-17.md. Signal: desks/release/.signals/20261017T162000Z.json.
