# docs-release — 2.1.8 release notes (2026-11-06)

Desk: `docs-release` (writer, docs only). Dispatch: the Lead's brief delivered in-session
(`bench/briefs/` carries no `brief_docs-release_2026-11-06.md`; the lane ran on the Lead's
message + the central ledger's 2026-11-06 block). Version target **2.1.8** (operator-approved;
`release-version` restored the 8 fields — re-verified at close: 7 TOCs line 6 + `main.lua:5`
all read `2.1.8`).

Verdict: **DONE (prose)**. `CHANGELOG.md` has a new `## [2.1.8]` section above `## [2.1.7]`
(history untouched); `README.md`'s What's New heading and body sentence now say **v2.1.8** and
a concise 2.1.8 display/power-bar/bar-text subsection was added. No `.lua`, TOC, `tests/`,
version field, `bench/` history, other desk file or git command was touched.

## 1. Scope held exactly

Write scope: `README.md`, `CHANGELOG.md`, `desks/docs-release/**`, one new bench report
(this file). Proven by `git diff --name-only` (2 tracked files) and the untracked set (this
report + desk files only). No product file appears in the diff.

Line endings: both docs are **LF** in the current tree (0 CR lines before and after). The
2026-10-28 docs lane recorded CHANGELOG as all-CRLF; the current file is LF, so the file was
normalised after that lane (the 2.1.7 release pass most likely). This lane preserved the
current LF; it converted nothing.

## 2. Gate that touches the docs

Only one consumer of prose exists: `tests/toc_check.lua:495-1077` reads the
`- **The per-class sets.**` passage of `CHANGELOG.md`, locates it by content
(`^%-%s+%*%*The per%-class sets%.%*%*`), normalises CRLF, and compares the parsed keys against
`classes/*.lua` — never against line numbers. No suite reads `README.md`.

- `lua5.1 tests/toc_check.lua` after the edit → **1104 checks, 0 failures, exit 0**
  (the two CHANGELOG checks: "CHANGELOG.md is readable"; "carries the 'The per-class sets.'
  passage").
- The pinned passage is **byte-identical** to `HEAD` (programmatic extraction from
  `git show HEAD:CHANGELOG.md` vs the worktree; both 2530 chars). The new section only moved
  it down (1223 → 1244).
- Re-run after the Lead's factual correction (see §5): same **1104 / 0, exit 0**.

Full harness was **not** re-run by this lane (dispatch: "run `lua5.1 tests/toc_check.lua`
only"); it was green 57/0 on the settled tree per the Lead/display-fix records and cannot be
moved by a docs-only diff (nothing else in `tests/` reads prose).

## 3. CHANGELOG.md — new `## [2.1.8]`

Structure follows the file's existing style (`## [x]` + **Verification status** +
`### Fixed` bold lead-ins, sub-bullets where the change has legs):

| Subsection | Content |
|---|---|
| Verification status | offline only (red-first pins + mutation proofs); in-client secret opacity, `StatusBar` acceptance and the new `/st diag` counters explicit **UNCONFIRMED**; no in-client pass for 2.1.8; "verified in game" explicitly disclaimed |
| Fixed #1 | **Auto Shot Display (`main.lua`)** — heartbeat no longer dies with the range poll (guarded visibility/alpha passes, unconditional re-arm, disabled poll still runs them); same-event open on ranged START/UPDATE, shot receipt, autorepeat events; restricted weapon-stat read no longer flips `has_weapon` false (readable-only update, world-entry re-probe, START proves the hand + lazy build); numeric id 75 auto-repeat probe (cooldown path + events + 4/s tick backstop) |
| Fixed #2 | **Swing Payload Recovery (`swing_source.lua`)** — secret/malformed `PLAYER_SWING` duration recovered from the equipped speed (`UnitAttackSpeed` per hand / `UnitRangedDamage` ranged, pcall + secret-checked); only "no readable speed" is a counted reject; first-reject notice; diag counters |
| Fixed #3 | **Horizontal Range Bar (`weave_range.lua`, `main.lua`)** — unknown face only for target-present + attackable + distance unknown; no target / non-attackable still hides (corrected, §5); recoverable 25-throw quarantine (armed driver, last paint, 10 s→60 s backoff, clear on success); guarded idempotent init + one world-entry retry; `weave=` diag token |
| Fixed #4 | **Power Bar (`power_bar.lua`, `compat.lua`, `diag.lua`)** — raw `api.GetPlayerPower` + real `StatusBar` pass-through, `?` label while restricted, never compared/divided/formatted; readable rendering unchanged (and the documented fraction-0 difference disclosed: empty track vs the old 1 px sliver); diag `value=restricted fraction=?` |
| Fixed #5 | **Attack-Speed & Timer Text (`utils.lua`)** — nearest-tenth rounding; the 8 speeds named (1.4/1.9/2.3/2.4/2.8/2.9/3.3/3.8); 1.95 s → "2.0" half-up |
| Fixed #6 | **Bar Tick Cost (`bars.lua`)** — one clock read passed to `set_bar_texts`, cached spark decoration, one fill write at the end; 2026-10-28 resize repaint + fill-last unchanged |
| Changed | **Version 2.1.8** — 7 TOCs + `main.lua` (matches `release-version`'s own proof) |

No date was added (the file's sections carry none); no file:line citations, no bench paths,
no desk names.

## 4. README.md

- `## 🚀 What's New in v2.1.7` → **v2.1.8**; the callout body sentence rewritten to lead with
  the v2.1.8 display/power-bar/bar-text fixes while keeping the 2.1.7 feature summary as an
  accurate reference ("remain accurate for this release"). The `& TBC Anniversary (2.5.6)`
  launch phrase dropped from this release's headline (2.1.8 is a Forever display wave; TBC
  support is unchanged and still in the Supported Clients table).
- New `### ✨ WoW Forever Display, Range & Power Fixes (v2.1.8)` with 4 tight bullets
  (Auto Shot recovery incl. numeric 75; range-bar unknown face + recoverable driver + guarded
  init; secret power bar; bar text + tick).
- `### 🌟 Release Highlights` retitled `### 🌟 Release Highlights (v2.1.7)` so 2.1.7 content
  under a 2.1.8 heading cannot mislabel the new wave. `### 🛠️ WoW Forever Runtime Hardening
  (v2.1.7)` left as history (dispatch permitted).
- Final disclaimer tightened: "verified offline by the unit suites; in-client confirmation …
  still pending."
- No 2.1.7 string is left as a **live version claim**: the only remaining occurrences are the
  two historical subsection labels at `README.md:49` and `:70` (the gated ones by design).
  `grep -n '2\.1\.7' README.md` → exactly those two.

## 5. Late correction (Lead, before close)

The first draft's CHANGELOG range-bar bullet had the wrong parenthetical: "(no target,
`checkedDistance` false, non-finite or secret)". The fix report (§B-5) is explicit — the
unknown face is `target present + attackable + distance unknown`; **no target or a
non-attackable target still hides** the bar. Corrected in both files:

- CHANGELOG: "when a target is present and attackable but the client cannot answer the
  distance … ; no target or a non-attackable target still hides it."
- README bullet: same condition, same "still hides" clause; the callout sentence now says
  "when an attackable target's distance cannot be read" instead of "stays visible".

Everything else left as written. `toc_check` re-run after the correction: 1104/0, exit 0.

## 6. Evidence map (claim → source read for this lane)

| Claim in the docs | Evidence |
|---|---|
| heartbeat re-arm / guarded passes / disabled poll still shows-hides | `bench/display_fix_2026-11-06.md` §A-2 (R1), `bench/forever_display_audit_2026-11-06.md` A-2 |
| same-event open (START/UPDATE, shot receipt, autorepeat) | `bench/display_fix_2026-11-06.md` §A-2 immediate visibility |
| `has_weapon` readable-only + world re-probe + START proves the hand | `bench/display_fix_2026-11-06.md` §A-3/A-4 |
| numeric id 75 / 4 per second / cooldown + event paths | `bench/display_fix_2026-11-06.md` §A-4; audit A-4/V2 |
| swing duration recovery from equipped speed; no-speed reject; first-reject notice | `bench/display_fix_2026-11-06.md` §A-1; `bench/forever_display_audit_2026-11-06.md` A-1 |
| unknown face condition; no-target/non-attackable still hides | `bench/display_fix_2026-11-06.md` §B-5 ("target present + attackable + distance unknown") |
| recoverable quarantine, 10 s → 60 s, last paint kept | `bench/display_fix_2026-11-06.md` §B-6 |
| guarded init + one world-entry retry | `bench/display_fix_2026-11-06.md` §B-1 |
| `weave=` diag token | `bench/display_fix_2026-11-06.md` §B-7 |
| raw reader + StatusBar pass-through + `?` + unchanged readable rendering + fraction-0 note | `bench/powerbar_secret_2026-11-06.md` §1-§3 |
| `value=restricted fraction=?` | `bench/powerbar_secret_2026-11-06.md` §2 (diag) |
| 8 truncated speeds / half-up / 1.95 s → 2.0 | `bench/bars_perf_fix_2026-11-06.md` §A4 |
| clock reuse / spark cache / single fill / resize contract kept | `bench/bars_perf_fix_2026-11-06.md` §A1-A3 |
| version 2.1.8 in 7 TOCs + main.lua | `desks/release-version/journal.md` + re-verified live at close |

Nothing in the docs cites a number, date or behaviour not in these reports.

## 7. Explicitly excluded / not claimed

- **No in-client claim.** The offline-only disclaimer is in both files (CHANGELOG
  Verification status; README section footer). The real secret surface, tainted `StatusBar`
  acceptance, `WHITE8X8` presence, font layering, `checkedDistance` frequency and the diag
  counters all stay UNCONFIRMED.
- No internal desk names, bench paths, "audit" jargon, file:line citations or test names in
  user docs.
- No version bump, no TOC/test/code edit, no git command.

## 8. Close-out checks (commands and results)

- `grep -n '2\.1\.8' README.md CHANGELOG.md` → README 37/40/42; CHANGELOG 3/5/22.
- `grep -n '2\.1\.7' README.md` → only the two historical subsection headings (49, 70).
- `git diff --stat -- README.md CHANGELOG.md` → 2 files, +32/−4 (CHANGELOG +21, README +15/−4);
  `git status --porcelain` scoped to the desk → only those 2 + this report/desk files.
- `file README.md CHANGELOG.md` + CR count → UTF-8, 0 CR lines each (LF preserved).
- Heading audit: README `##`/`###` sequence intact, no empty/duplicate headings.
- `lua5.1 tests/toc_check.lua` → **1104 checks, 0 failures, exit 0**; pinned passage
  byte-identical to HEAD; re-run after the §5 correction identical.

Final hashes: `README.md` `976000eb2b535fedace451926a24a59516b9b5317b8a54562c5d5aaefd98d589`;
`CHANGELOG.md` `f93d78f690d0a4df534a93a9e3c4a10bd7637150daf91ad3a6485c6144c91936`.

## 9. Gaps / owed

- **In-client Forever pass** (operator) is the only close for every UNCONFIRMED item; the
  docs say so.
- The docs describe the 2.1.8 wave only; the A-5/A-7 follow-ups and the stale
  `tests/secret_guard_state.lua` representation are not user-visible and are not mentioned
  (they belong in the audit/trail, not release notes).
- The `README` still calls the badge "WoW Forever 1.60.1 Ready" — unchanged, and not falsified
  by this wave.

## 10. Extension — secret-value hardening block (same day, second pass)

Dispatched after the secret-value fix wave closed (final gate green: `tests/run.sh` 57/0,
`luacheck` 2/0, version 2.1.8). Evidence read for this pass:
`bench/secret_api_matrix_2026-11-06.md`, `bench/secret_consumers_audit_2026-11-06.md`,
`bench/secret_core_fix_2026-11-06.md`, `bench/secret_guide_fix_2026-11-06.md`,
`bench/secret_hud_fix_2026-11-06.md`, plus the central ledger's final secret-wave
reconcile.

Added:
- `CHANGELOG.md` — a `### Hardening` subsection inside `## [2.1.8]` (one bold lead-in +
  5 sub-bullets: restricted reads as unknown/`inputs_unknown` incl. the latent paladin
  mana-compare crash; ToT `SetAlphaFromBoolean` pass-through; HUD trinket grey-unknown
  face; hunter `api.UnitGUID` + aura-scan + `UnitCreatureType` guards; compat hardening
  incl. the additive helpers and the fourth `restricted` return). Verification-status
  line extended with the final gate numbers plus "secret triggers and rendering".
- `README.md` — new `### 🔒 Secret-Value Hardening (WoW Forever, v2.1.8)` block (5 bullets)
  after the display/range/power subsection, and one clause in the What's New callout so
  the headline covers the hardening wave. The existing power-bar StatusBar bullet is kept
  unchanged as instructed.

Claim map (all from the five reports; no new numbers invented):

| Claim | Source |
|---|---|
| restricted cooldown/power/target-aura/target-health -> nil + `inputs_unknown`; guide withholds; Judgement/Arcane/Rend/Rip/Rake/Flame Shock/Enrages | `secret_guide_fix` §1-2; `secret_consumers_audit` H1/H2/H4 |
| latent paladin mana-compare crash fixed (four filler gates on `mana_known`) | `secret_guide_fix` §7.1 + mutation M10 |
| restricted `UnitIsUnit` -> `SetAlphaFromBoolean`; readable path unchanged; one-time notice without the method | `secret_core_fix` SEC-2/M1 |
| trinket slot kept grey-unknown (no swipe/text); readable passive hides | `secret_hud_fix` root cause + fix |
| hunter `api.UnitGUID`; 3 aura scans walk past restricted rows; `UnitCreatureType` unknown is not "not undead" | `secret_core_fix` SEC-1/SEC-7/SEC-3 |
| classic `UnitAura` precheck+pcall; ratings guarded; 5 additive helpers/fourth return | `secret_core_fix` SEC-4/SEC-11 + shared helpers; `secret_guide_fix` §2 |

Verification after the extension: `grep -n '2\.1\.8'` → README 37/40/42/49,
CHANGELOG 3/5/31; README `2.1.7` only the two historical labels (`:57`, `:78`); pinned
CHANGELOG passage byte-identical to HEAD (2530 chars); scoped diff 2 tracked files —
total vs HEAD `+49/−4` (CHANGELOG +30, README +19/−4; this pass added +9 and +8 lines
respectively); LF preserved (0 CR); `lua5.1 tests/toc_check.lua` 1104/0, exit 0.
