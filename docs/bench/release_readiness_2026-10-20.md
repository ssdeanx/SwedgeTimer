# Release readiness — packaging and release mechanics (2026-10-20)

**Lane:** `release-readiness` · session `ses_ea50b69a3ffeho4fG41TPP7VZ1` (ledger row
`desks/journal.md:294`) · **Scope:** READ-ONLY except this file.
**Question answered:** what must be true mechanically before the build can be published,
and what is left to the operator.
**Plan reference:** `bench/final_completion_plan_2026-10-19.md` § Phase 9 (release decisions).

**Verdict: the build is mechanically publishable; the RELEASE ITSELF is not ready to
upload.** The code side is green and consistent (versions agree 8/8, TOC coverage is
complete with zero orphans and zero case errors, every media file the code loads by path
exists). Four items are open, and all four are the operator's or the orchestrator's, not
the code's:

| # | Item | Severity | Owner |
|---|---|---|---|
| F1 | CHANGELOG release body is missing the newest landed lane (the offer gate) | **release blocker** (docs) | operator / changelog lane |
| F2 | No package manifest or build script — a naive "zip the repo" ships 249 MB, of which 183 MB is unreferenced media | **release blocker** (packaging) | operator |
| F3 | The trail has 4 broken desk records (1 missing journal, 2 missing signals, 1 unparsable signal) and a structurally untraceable ledger | medium (hygiene) | orchestrator |
| F4 | Version still 2.1.1 — this wave is a feature wave; the release body and the version line must agree | medium | operator (decision), version-bump lane (mechanics) |

---

## 1. Version truth

### The eight live version fields — all agree

| Field | File:line | Value |
|---|---|---|
| TOC version | `SwedgeTimer.toc:6` | `## Version: "2.1.1"` |
| TOC version | `SwedgeTimer_Vanilla.toc:6` | `## Version: "2.1.1"` |
| TOC version | `SwedgeTimer_TBC.toc:6` | `## Version: "2.1.1"` |
| TOC version | `SwedgeTimer_Wrath.toc:6` | `## Version: "2.1.1"` |
| TOC version | `SwedgeTimer_Cata.toc:6` | `## Version: "2.1.1"` |
| TOC version | `SwedgeTimer_Mists.toc:6` | `## Version: "2.1.1"` |
| TOC version | `SwedgeTimer_Mainline.toc:6` | `## Version: "2.1.1"` |
| Runtime version | `main.lua:5` | `local version = "2.1.1"` |

**8/8 agree — PASS.** `main.lua:6` (`-- local version = "2.0"`) is a deliberately kept
comment (the version-bump brief: `bench/briefs/brief_version-bump_2026-10-19.md:16`), not a
live field.

**OPERATOR RULING (2026-10-20, final): the release is 2.1.1 — NO version bump.** The
recommendation that follows is **superseded** and kept only as the record of what was
proposed. Do not edit the version in any of the 8 fields and do not add a `[2.2.0]` CHANGELOG
header.

### The documents that carry a version

| Document | Verdict |
|---|---|
| `CHANGELOG.md:3` | `## [2.1.1]` — **matches** the TOC/main.lua version. Next header is `## [2.0.8]` at `CHANGELOG.md:895`, so the `[2.1.1]` section spans **lines 3–894**. |
| `README.md` | **No version string anywhere** (100 lines, zero `2.x.y` matches). Nothing to mismatch — but also nothing that would go stale on a bump. The README was rewritten since the 2026-10-19 audit, which found `README.md:61` reading `current: 2.1.1`; that line is gone now. |
| `TESTING.md:43`, `TESTING.md:49` | `version=2.1.1` in both `/st diag` example outputs — **matches**. (The 2026-10-19 audit's F2, "TESTING.md:33 still `version=2.1.0`", is **closed**; the diag block moved to lines 43/49.) |
| `desks/journal.md:9` | Ledger Status block says "Version **2.1.1** in all 7 tocs + main.lua" — **matches** the tree (the same sentence's harness numbers are stale; see §5). |

### Is a bump needed? — **NO. The version stays 2.1.1 (operator ruling, 2026-10-20).**

**Operator ruling (final):** the release is **2.1.1**. No bump, no skip, no "minor version
because it is a feature wave" reasoning. The operator is publishing this as 2.1.1 and
explicitly rejected a 2.2.0 recommendation. The section below (the original "recommend
2.2.0" argument) is **superseded** and kept only as the record of what was proposed; it is
NOT the decision.

Do **not** edit the version in any of the 8 fields (`## Version:` in all 7 TOCs, `main.lua`'s
`version`) and do not add a `[2.2.0]` CHANGELOG header. The tree's 8 fields already agree at
**2.1.1** and the CHANGELOG's top section is `## [2.1.1]` — that is the release.

The original argument (superseded):

The plan's own Phase 9 says so: *"everything new landed under `2.1.1`. A feature release
wants a bump (2.2.0); the operator decides (they set 'no version bump' earlier, before this
wave existed)"* (`bench/final_completion_plan_2026-10-19.md:95-96`). The "no bump" was
recorded before this wave existed, so the condition it was given under no longer holds.

This wave is a **feature** wave, not a fix wave — semver says minor, 2.1.1 → **2.2.0**.
What landed since 2.1.1 (all cited in the release body, `CHANGELOG.md:763-893`, plus the
one entry still missing — F1):

- the **NEUTRAL** engine outcome — a new grade class, new accessor, new panel wording
  (`CHANGELOG.md:765-779`)
- **per-class neutral action sets** for all six classes + the **practice-panel common
  ability list** (`ST.<CLASS>.practice_common_actions`) — new published surfaces
  (`CHANGELOG.md:780-800`)
- the **shaman's family-scoped practice surface** (`ST.SHAMAN.practice_rotation_for(family)`,
  `family_guide_slots`, `apply_family_slots`) — new API, new per-family slot sets
  (`CHANGELOG.md:801-817`)
- the **hunter's per-family HUD slot ids** (`SPELL_ID_BY_FAMILY`) — new behaviour
  (`CHANGELOG.md:818-827`)
- the **Wglass** status-bar texture as the operator-gated default status-bar medium
  (`main.lua:331-340`) — a **default-visible change**
- the **offer gate** (`ST.<CLASS>.practice_common_offer_allowed`) in all six class files —
  new shipped behaviour, **not yet in the CHANGELOG** (F1)
- the progression fixes (`CHANGELOG.md:828-…`) and the strict pick / pre-pull contracts
  (`CHANGELOG.md:860-874`)

**Recommendation: bump to `2.2.0`.** It is a feature release (new user-visible surfaces and
a new default), the version is a marketing/identity string the operator publishes, and a
minor bump is what semver prescribes. If the operator prefers to keep 2.1.1, then F1 below
becomes *mandatory* instead of recommended (the release body must then be the `[2.1.1]`
section as it stands — which is missing the newest lane).

**Bump mechanics, when ordered (8 fields, no more):** the `## Version:` line of all seven
TOCs (line 6 in each) and `main.lua:5`. Do **not** touch `main.lua:6`, the `## Interface:`
lines, or the load orders. `TESTING.md:43,49` and `README.md` carry no version that needs
updating. `CHANGELOG.md` needs a **new `## [2.2.0]` header** at line 3 (the release body
becomes lines 3–(whatever the new section ends at)) — not an edit of `[2.1.1]`.

---

## 2. TOC coverage verdict — **PASS, no orphans, no case errors, one documented divergence**

### Method

Read all 7 `SwedgeTimer*.toc` files and compared their entry lists against the real
directory entries (case-sensitively, via `ls`, not an existence test — a plain existence
check would let the historic `AceEVent-3.0.xml` typo through on a case-sensitive loader,
per `tests/toc_check.lua:1-7`). Then compared the seven entry sequences against each other.
Cross-checked against the repo's own offline check, which is re-run below.

### 2.1 Files loaded by NO toc (silent no-op) — **NONE**

- 44 `.lua` modules exist: **38 in the repo root**, **6 in `classes/`**.
- **44/44 are listed in every one of the 7 TOCs.** Zero orphans.
- 61 entries per classic-line toc, 60 in Cata/Mists/Mainline (the one documented
  omission, §2.3).
- The repo's own check pins this independently: `tests/toc_check.lua:260-266`
  ("every addon .lua module on disk is listed") — **green**.
- Nothing outside the addon is TOC-listed: `bench/`, `desks/`, `tests/`, `docs/swedge/`
  (the two archived addons) and the `Libs/` trees are not in any toc except `Libs/`,
  which is intentional.

### 2.2 Files loaded with a case mismatch — **NONE**

Every entry of every toc (including all `Libs/` entries) was matched case-sensitively
against the real directory listing: **0 mismatches, 0 missing files, 0 directory errors**
across **424 entries** (the four classic-line tocs carry 61 each = 244; Cata/Mists/Mainline
carry 60 each = 180). The repo's own check pins this at `tests/toc_check.lua:178-181`
("exists", case-sensitive) — **green**.

### 2.3 Files loaded in a different order across flavors — **one divergence, the documented one**

| TOC | Divergence from the base toc |
|---|---|
| `SwedgeTimer.toc` | — (reference) |
| `SwedgeTimer_Vanilla.toc` | **identical** (same set, same order) |
| `SwedgeTimer_TBC.toc` | **identical** |
| `SwedgeTimer_Wrath.toc` | **identical** |
| `SwedgeTimer_Cata.toc` | set-difference = **omits** `Libs\LibClassicSwingTimerAPI\LibClassicSwingTimerAPI.lua` (base line 18). **Order on the common subset is identical.** |
| `SwedgeTimer_Mists.toc` | same omission, same identical common order |
| `SwedgeTimer_Mainline.toc` | same omission, same identical common order |

This is the **documented and intended** divergence — `AGENTS.md` ("Cross-engine"): the
swing-engine library is classic-line only; its file-scope
`RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` throws on mainline-code clients, and its
spell tables stay nil on Cata/Mists. The repo pins **both directions**
(`tests/toc_check.lua:278-300`: ships on Vanilla/TBC/Wrath, does not ship on
Mainline/Cata/Mists) — **green**. **No undocumented divergence exists.**

### 2.4 Load order — deps before dependents: **verified**

Order pins, all satisfied identically in all 7 tocs (base-toc line numbers; the Cata/Mists/
Mainline line numbers are one lower from line 18 onward):

| Dependency | Base toc lines | Independent evidence |
|---|---|---|
| `compat.lua` < `swing_source.lua` < `main.lua` | 23 < 24 < 58 | `swing_source.lua` needs `st.family`/`st.api`; `main.lua` reads `st.swing_source` while it loads |
| `utils.lua` < `guard.lua` < every consumer | 38 < 39 < 59/61/62/63/65 | `guard.lua` is the shared isolation contract; consumers `bars.lua`, `nextaction_ui.lua`, `practice_ui.lua`, `hud.lua`, `rotationtext.lua` (`tests/toc_check.lua:123-127, 209-223`) |
| `twist.lua` < `weave.lua` < `main.lua` | 41 < 42 < 58 | pure modules |
| `druid_energy.lua` < `classes\druid.lua` | 44 < 72 | **`classes/druid.lua:65` captures `st.druid_energy` at file scope** — a real load-time dependency, satisfied |
| `config_presets.lua` < `config.lua` | 67 < 70 | **`config.lua:64` reads `ST.class_defaults` at file scope**, which `config_presets.lua:27` defines — the `AGENTS.md` gotcha, satisfied |
| `practice_stats.lua` < `practice_progress.lua` < `practice_progress_ui.lua` | 55 < 56 < 57 | `practice_progress.lua:1336` reads `st.practice_stats`; `practice_progress_ui.lua:32` documents the adjacency |
| `nextaction.lua` < `nextaction_ui.lua` | 45 < 61 | `nextaction_ui.lua:695` reads `st.nextaction` |
| `design.lua` < `designmode.lua` | 51 < 66 | `designmode.lua:456` reads the design maths |
| `main.lua` < every `classes\*.lua` | 58 < 72-77 | class modules are initialised from `main.lua`'s `post_init` |
| `classes\rogue.lua` > `classes\warrior.lua` | 77 > 76 | the class block's established tail |

### 2.5 The interface matrix (what each flavor claims)

| TOC | `## Interface:` (line 1) | Notes |
|---|---|---|
| `SwedgeTimer.toc` | `11509, 20506, 38002` | classic-line **fallback** only (F6 narrowing: it ships `LibClassicSwingTimerAPI`, whose file-scope CLEU `RegisterEvent` aborts the whole load on a mainline-code client) |
| `SwedgeTimer_Vanilla.toc` | `11509` | Era / SoD |
| `SwedgeTimer_TBC.toc` | `20506` | TBC Anniversary |
| `SwedgeTimer_Wrath.toc` | `38002` | WotLK Titanforge |
| `SwedgeTimer_Mainline.toc` | `120100, 120105, 16001` | Retail + WoW Forever |
| `SwedgeTimer_Cata.toc` | `40402` | shipped, **not a supported client** (README:14) |
| `SwedgeTimer_Mists.toc` | `50500` | shipped, **not a supported client** (README:15) |

`tests/toc_check.lua:302-340` pins the exact values for Vanilla/TBC/Wrath, the *contains*
set for Mainline and the base toc, and asserts that **30401 (WotLK Classic) is not a
target**. Cata/Mists values are parse-checked but not pinned exact — a standing pattern,
not a finding (same as the 2026-10-19 audit).

### 2.6 The whole tree, re-run in-lane (read-only execution, no edits)

`bash tests/run.sh` → **43 steps, 0 failed**; luacheck → **2 warnings / 0 errors in 85
files** (the standing floor; both warnings pre-existing, in `compat.lua` and `main.lua`).
This includes `tests/toc_check.lua` and `tests/wiring_check.lua`. The harness writes only
to a `mktemp -d` scratch dir (`tests/run.sh:14-16`), so the tree was not modified.

---

## 3. Media — every file the code loads by path exists

### 3.1 The precedent, confirmed

`Media/Textures/Minimalist.tga` is **not TOC-listed** and still loads, because the shipped
code addresses it by an **absolute path inside the addon folder** and registers it with
LibSharedMedia at runtime:

- `main.lua:328-330` — `LSM:Register("statusbar", "Minimalist", [[Interface\Addons\SwedgeTimer\Media\Textures\Minimalist.tga]])`
- `bars.lua:41` — `local FALLBACK_STATUSBAR_KEY = "Minimalist"` (the degradation target)
- `tests/options_load_state.lua:4285-4286`, `tests/bars_state.lua:2682-2710` pin that the
  key stays registered and that the fallback still degrades to it.

**The precedent holds for every media file in the addon: custom media is loaded by
runtime path, never by a TOC line.** So the TOC does not need to list any of them — but
they **do** need to be inside the shipped folder. That is exactly the packaging
requirement in §4.3.

### 3.2 The complete list of media the shipped code references by path — all present

| # | Media | Referenced at | Exists |
|---|---|---|---|
| 1 | `Media/Fonts/Expressway.ttf` | `main.lua:326` (LSM font "Expressway") | ✅ |
| 2 | `Media/Textures/Minimalist.tga` | `main.lua:329` (LSM statusbar "Minimalist") | ✅ |
| 3 | `Media/StatusBar/Wglass.tga` | `main.lua:339` (LSM statusbar "Wglass" — the operator-gated default texture) | ✅ |
| 4 | `Media/Textures/circle_smooth.tga` | `nextaction_ui.lua:124` (`HOLD_CIRCLE_TEXTURE`) | ✅ |
| 5 | `Media/Sounds/*.ogg` + `*.mp3` — **69 files** | `classes/paladin.lua:975-1053` (the `twist_sounds` map; published as `ST.PALADIN.twist_sounds` at `:1058`; played at `:1063-1068`, `:2005-2007`, `:2061`) | ✅ **69/69** |
| 6 | `SwedgeTimer_v2_transparent.tga` | the `## IconTexture:` header, **line 4 of all 7 TOCs** | ✅ (4.19 MB) |
| — | `Interface\Buttons\WHITE8X8`, `Interface\Tooltips\UI-Tooltip-*`, `Interface\Icons\*` | `bars.lua:42`, `hud.lua:844`, `practice_ui.lua:233-235`, `practice_progress_ui.lua:889-890`, `practice.lua:96,137,1008` | client built-ins — **not addon files, nothing to ship** |

**Referenced addon media: 73 files, 0 missing.** (`Media/Sounds/` holds exactly 69 files
and the map references exactly 69 — a 1:1 match, no orphans in either direction.)

`SwedgeTimer_v2_transparent.png` (1.5 MB) sits at the repo root but is **not** referenced by
any toc — it is a project-page asset for the operator, not addon payload.

### 3.3 Unreferenced media — 371 files, 183 MiB, in the addon folder

`Media/` holds **444 files (185.2 MiB)**; the code loads **73 (1.97 MiB)**. The other
**371 files / 183.2 MiB** are referenced by **nothing** in the shipped tree:

| Directory | Files | Size | Referenced? |
|---|---|---|---|
| `Media/Class_icons/` | 224 | **173 MB** | no |
| `Media/StatusBar/` (everything except `Wglass.tga`) | 65 | 5.4 MB | no |
| `Media/blizz_textures/` | 55 | 2.7 MB | no |
| `Media/Background/` | 7 | 2.2 MB | no |
| `Media/Platynator/` | 11 | 252 KB | no |
| `Media/Details/` | 4 | 1.4 MB | no |
| `Media/Textures/` (except `Minimalist.tga`, `circle_smooth.tga`) | 5 | — | no |

Two extra facts for the packaging decision:

- **229 of the 444 `Media/` filenames contain a literal backslash** — e.g.
  `Media/Class_icons/RondoMedia\media\Class_icons\class_colored border\32x32\Monk_32.tga`.
  A zip built on Linux stores that backslash as a character in the filename, and a Windows
  client cannot resolve it into a directory separator. These files are unreachable by
  design **on every shipped client platform**. None of the 73 referenced files has a
  backslash in its name.
- `Media/` is **not** in `.gitignore` (`.gitignore` covers `log/`, `log.txt`, `.hermes/`,
  `undefined/`, `.omo/run-continuation/*`, `docs/media/`, `OLD/`), so the bloat is tracked.

### 3.4 One packaging constraint the code hardcodes

Every addon-relative path in the tree is
`Interface\AddOns\SwedgeTimer\…` / `Interface\Addons\SwedgeTimer\…` — the folder inside
the zip **must be named `SwedgeTimer`**, exactly. A zip whose top folder is named
differently (or a zip whose contents are the files without a wrapper folder) breaks every
media path, the font, the status-bar textures, the HOLD overlay and all 69 sounds.

*Casing note (LOW):* `main.lua:326,329,339` use `Interface\Addons\SwedgeTimer` (lower-case
"d") while `classes/paladin.lua:977-1053` and `nextaction_ui.lua:124` use
`Interface\AddOns\SwedgeTimer` (capital "O"). Windows and macOS are case-insensitive by
default, so both resolve on every shipped client platform — no fix needed for the
release; worth normalizing later for tidiness.

---

## 4. The publish checklist for the operator

### 4.1 What is already in place

| Item | Where | State |
|---|---|---|
| One universal build, per-flavor dispatch | 7 tocs, `## Interface:` line 1 each | ✅ |
| Version fields | 8/8 at `2.1.1` | ✅ consistent (but see §1) |
| Addon icon | `SwedgeTimer_v2_transparent.tga` at the addon root, `## IconTexture:` line 4 of every toc | ✅ |
| Project identifiers | `## X-Wago-ID: 9rN4dMND`, `## X-WoWI-ID: 26295`, `## X-Curse-Project-ID: 621214` — **identical in all 7 tocs**, lines 10–12 | ✅ the IDs are already in the tree; only the live URLs are missing |
| CurseForge/WoWI/Wago upload metadata | `## Notes:`, `## Author: Swedge`, `## OptDeps: Ace3, LibSharedMedia-3.0, LibStub`, `## SavedVariables: SwedgeTimerDB` (toc lines 3, 5, 8, 9) | ✅ |
| Release body | `CHANGELOG.md` lines **3–894**, the `## [2.1.1]` section | ✅ present — **but see F1** |
| README | 100 lines: supported-client table (incl. the two non-supported shipped flavors, lines 14-20), install, slash commands, classes, practice, HUD/designer | ✅ |
| In-client acceptance checklist | `TESTING.md` (408 lines), diag examples at `2.1.1` (`:43`, `:49`) | ✅ |
| Operator's live script | `bench/live_test_script_2026-10-19.md` (81 KB) | ✅ |
| Offline verification | `bash tests/run.sh` → **43 steps / 0 failed**; luacheck 2 warnings / 0 errors in 85 files | ✅ |
| Documentation truth | the 2026-10-19 release audit's F2 (`TESTING.md` stale version) is **closed**; its F1 (CHANGELOG coverage of ~60 late lanes) is **closed for the 2026-10-19/20 waves** | ✅ except F1 below |

### 4.2 The exact release body

> **`CHANGELOG.md`, the `## [2.1.1]` section — lines 3 through 894 inclusive.**
> It ends at line 893 (the last bullet of the 2026-10-20 wave) and line 895 is the next
> release header, `## [2.0.8] -- 2023-05-09`.

Its subsections, in order: `### Added` (5), `### Changed` (77), `### Fixed` (83),
`### Guidance, HUD and design mode` (118), `### Build-out round + hardening` (148),
`### Rogue sixth class` (207), `### Final hardening` (277),
`### Practice/designer wave` (285), `### Rotation scenarios + per-class drills` (298),
`### Practice gamification` (338), `### Audit fixes` (399), `### Closure wave` (456),
`### Scenario surface + APL utility layer` (498), `### Audit-fix wave` (665),
`### Neutral actions, family scope, HUD ids, progression and contracts` (763).

**Every subsection ends with a "verified offline, UNCONFIRMED in-client" marker** — the
in-client pass is still owed, and the operator's own script + `TESTING.md` are that pass.

### 4.3 The package build (F2 — nobody has built it yet)

There is **no `.pkgmeta`, no build script, no CI workflow, no packaging macro** in the
repo (only `tests/run.sh` exists). The package is a hand-made zip, and the addon folder
**is the repo root** — so a naive "zip the repo" would publish the workshop.

| | naive repo-root zip | trimmed package |
|---|---|---|
| size | **249 MB** (278 MB with `.git/`) | **9.9 MB** |
| includes `bench/`, `desks/`, `tests/`, `docs/swedge/`, `.vscode/`, `.ruff_cache/`, `luac.out` | yes (51 MB of workshop material) | no |
| includes `.git/` | yes (29 MB) — normally excluded, but nothing in the repo excludes it for you | no |
| includes `Media/Class_icons/` (unreferenced) | yes (173 MB) | no |
| includes `Media/blizz_textures/`, `Media/Background/`, `Media/Platynator/`, `Media/Details/`, unreferenced `Media/StatusBar/*` | yes | no |

**Recommended package manifest** (a `SwedgeTimer/` folder containing):

```
SwedgeTimer/
  SwedgeTimer.toc            SwedgeTimer_Vanilla.toc   SwedgeTimer_TBC.toc
  SwedgeTimer_Wrath.toc      SwedgeTimer_Cata.toc      SwedgeTimer_Mists.toc
  SwedgeTimer_Mainline.toc
  <38 root .lua>   classes/   (6 .lua)
  SwedgeTimer_v2_transparent.tga
  Media/Fonts/Expressway.ttf
  Media/Textures/Minimalist.tga
  Media/Textures/circle_smooth.tga
  Media/StatusBar/Wglass.tga
  Media/Sounds/  (69 files)
  Libs/  (the whole vendored tree, as the tocs require)
```

**Exclusions** (each justified): `bench/`, `desks/`, `tests/`, `docs/` (archived addons —
`AGENTS.md`: "not part of the shipped addon"), `.git/`, `.vscode/`, `.ruff_cache/`,
`.luacheckrc`, `luac.out` (a 137 KB Lua-bytecode scratch file at the repo root),
`CHANGELOG.md`/`README.md`/`TESTING.md`/`LICENSE` (harmless if included; the client ignores
them, but they are not addon payload), `AGENTS.md`/`CAIRN.md`/`workshop.md`/`hands-up.md`,
`Media/Class_icons/` + the other 371 unreferenced media files, and
`SwedgeTimer_v2_transparent.png` (keep it beside the zip for the project page, not inside
it).

Note: the tocs reference `Libs\` paths, so **the whole `Libs/` tree must ship** — it is
not optional and not replaceable by the CurseForge "libraries" mechanism without a
`.pkgmeta` that does not exist.

### 4.4 What is owed by the operator

1. **The version decision** (§1). Recommendation **2.2.0**; the bump is 8 fields.
2. **One CHANGELOG entry for the newest lane** (F1) — or a `## [2.2.0]` header that
   contains it.
3. **The package build** (F2) — §4.3's manifest, folder named `SwedgeTimer`.
4. **Screenshots** — `README.md:22-24` still reads *"PENDING — screenshots to be added. No
   images yet."* The repo has `SwedgeTimer_v2_transparent.png` (the addon logo, suitable as
   the project icon) but **no gameplay screenshot**; the operator must capture them
   in-client (the bars, the cooldown HUD, the practice panel, the Progress page).
5. **The project URLs** — `README.md:96`: *"CurseForge (search `SwedgeTimer` …), with Wago
   and WoWInterface listings. Exact project-page URLs unconfirmed; no links invented
   here."* The **ids are already in the tree** (`X-Curse-Project-ID: 621214`,
   `X-Wago-ID: 9rN4dMND`, `X-WoWI-ID: 26295`); the operator only needs to confirm the live
   URLs and paste them into README:96. (Consistency note: the README's "Supported
   clients" table also lists Cata/Mists as *not* supported while the tocs ship them —
   that is deliberate and documented at `README.md:17-20`.)
6. **The in-client acceptance pass** — `TESTING.md` (408 lines) plus
   `bench/live_test_script_2026-10-19.md`. Every changelog claim is marked offline-only;
   the release body cannot be called verified until this runs. This is the operator's
   session, not the build's.
7. **The upload itself** — CurseForge (id 621214) / Wago (9rN4dMND) / WoWInterface (26295),
   with the release body from §4.2 and the version from §1.

---

## 5. Trail consistency verdict — **4 broken records + one structural gap**

### 5.1 `workshop.md` → desk journals

`workshop.md:41-59` lists **78 desks**; `workshop.md:37-40` says the list was *"verified
2026-10-19 against the tree"* and that **the central lane table in `desks/journal.md` is
the only authoritative lane table, not this list**.

- **77 of the 78 listed desks have a `journal.md`.**
- **1 does not: `rogue-rotation`** — `desks/rogue-rotation/` contains only an **empty**
  `.signals/` directory, no `journal.md`. It is listed in `workshop.md:52` and has a
  `done` ledger row (`desks/journal.md:92`, session `ses_eab9e7983ffeRAuHBSLfqRecFc`).
- The list has also **rotted in the other direction**: **205 desk directories** now exist
  on disk, **127 of them are not in `workshop.md`** (all the 2026-10-20 lanes). Per the
  file's own wording this is not a defect — the lane table is authoritative — but the
  snapshot should either be refreshed or explicitly marked as a historical list.

### 5.2 `desks/journal.md` ↔ the desks — the session ids are **not** traceable

`desks/journal.md` has **273 lane rows** (260 distinct lane names — 12 names appear on
more than one row, e.g. `practice-hook` ×3, `final-gate-audit` ×2, `progress-page` ×2);
**25 rows are not in state `done`** — of those, `120105-matrix` is
`done (orchestrator direct, verified: toc_check 732/0, CRLF kept)` and `hunter-followups`
has a placeholder state cell `—`, so **22 rows are genuinely open**).

**The structural gap:** the ledger's fourth column holds the **dispatch session id**
(`ses_…`), but **no signal file in the workshop records a session id**. The signal format
in use is the `signal-write` template with `run_id` = `"<desk>-<date>"` and `agent_name`
= the desk name (e.g. `desks/changelog-truth/.signals/2026-10-20T151000Z.json`) — the
template has no session field. Consequence: **253 of the 258 lane rows that carry a session id have a session id that
appears in no signal file**, so the ledger's ids cannot be verified against the desk
records as the objective requires. A lane row's session id is therefore **currently
unfalsifiable** — the only honest check is desk-identity + artifact + signal subtype.

**The four broken records that check does catch:**

| Desk | Defect | Ledger row |
|---|---|---|
| `desks/rogue-rotation/` | **no `journal.md`**, and `.signals/` is **empty** (no signal file at all) | `desks/journal.md:92` — `rogue-rotation … done ses_eab9e7983ffeRAuHBSLfqRecFc` |
| `desks/warrior-desync/` | `journal.md` present, `.signals/` **empty** | `desks/journal.md:88` — `warrior-desync … done ses_eabe878d0ffe78UzfD09d3ZEnk` |
| `desks/progression-audit/` | `journal.md` present, **no `.signals/` directory at all** | `desks/journal.md:276` — `progression-audit … done ses_ea616dd2cffeWFceVBxbz3Z2Ok` |
| `desks/rogue-deep/.signals/2026-10-19T09:59:27Z.json` | **invalid JSON** — a shell echo line was appended after the closing brace (`…}\necho saved 2026-10-19T09:59:27Z; ls desks/rogue-deep/.signals/`), so the dashboard cannot parse it | `desks/journal.md` row for `rogue-deep` |

One **schema drift**, not a break: `desks/reconcile/.signals/2026-10-17T15-03-30Z.json`
uses a different shape entirely (`status`, `artifacts`, `validation`, no `signal_type` /
`subtype`). The dashboard reads `subtype` with a fallback to `signal_type` — **neither is
present**, so it cannot classify that signal.

**160 of the 273 lane rows name a lane with no desk directory at all** (e.g. `core-wiring`,
`options-grade`, `gap-closure`, `audit-wave`, `wa-gallery`, `live-test-script`,
`readme-production`). Most are historical waves whose work is recorded under a different
desk name or only on the bench — this is the naming drift of an organic ledger, not
evidence of lost work. It does mean **the ledger's lane names are not desk names**, and a
checker that assumes they are will produce false positives.

### 5.3 Lane rows still open (25) — what the operator needs to close

Rows whose work **has landed** (bench artifact + a `done` signal on a matching desk) and
whose row still says `running`/`queued` — **stale rows**:

| Row | Line | Evidence the work landed |
|---|---|---|
| `shaman-slots` | `:229` | `desks/shaman-slots/` — 1 `done` signal; `bench/shaman_slots_2026-10-19.md` |
| `superseded-wrappers` | `:230` | `desks/superseded-wrappers/` — 1 `done` signal; `bench/superseded_wrappers_2026-10-19.md` |
| `resolver-callers` | `:237` | `desks/resolver-callers/` — 1 `done` signal; also a `done` row at `:223` |
| `practice-hook` | `:238`, `:242` | `desks/practice-hook/` — 1 `done` signal; also a `done` row at `:225` |
| `f10-shared-guard` | `:239` | `desks/f10-shared-guard/` — 1 `done` signal; also a `done` row at `:245` |
| `prepull-contract` | `:285` | `desks/prepull-contract/` — 1 `done` signal; also a `done` row at `:295` |
| `progress-page` | `:235` | `desks/` has no `progress-page` dir, but a `done` row with a session id exists at `:224` |
| `practice-every-class` | (row `halted-superseded`) | `desks/practice/` — 2 `done` signals |
| `hunter-followups` | (state cell is `—`, not `done`) | `desks/hunter-followups/` — 1 `done` signal; the same session id is `done` on a later row |

Rows that are **genuinely open** and need an operator/orchestrator decision, not a
mechanical close: `full-feature-wave` (`:196`), `class-features-audit` (`:240`),
`drill-build-queue` (`:241`), `engine-hold` (`:257`), `warrior-hs-queue` (`:258` — its desk
journal's last line is *"Next step: the orchestrator validates and reconciles the
crossfire"*), `paladin-gate-widgets` (`:264`), `compat-known-contract` (`:265`),
`hunter-hud-slots` (`:286`), `final-gate-audit` (`:292`, `:298`), `final-gate-tests`
(`:293`), `designer-every-class`, `reconcile-note` (`:301`), and this lane's own row
(`:294`).

`neutral-buckets` (`:291`) **is** `done` — the ledger is current for the newest neutral
work; the stale rows are the older ones.

### 5.4 The ledger's own Status block is stale

`desks/journal.md:9-11` still says:

> "Harness: **37 steps, 0 failed** (verified in-tree 2026-10-19 …)" and
> "… Harness **38 steps**, 0 failed (floor)."

The tree is **43 steps / 0 failed** today (re-run in-lane, §2.6). The same line also says
"CHANGELOG [2.1.1] covers landings through the SoD-variants wave" — the CHANGELOG now
covers through the 2026-10-20 wave (`CHANGELOG.md:763-893`), minus the one newest entry
(F1). The Status block is the first thing a new desk reads, so it should be refreshed with
the release.

### 5.5 `bench/` ↔ `desks/journal.md` agreement — **one real disagreement**

- `bench/` holds **160 artifacts** (+ `bench/briefs/` with 59 briefs, + `bench/lessons.md`),
  all dated and named; the newest is `bench/class_neutral_family_coverage_2026-10-20.md`
  (16:12). Every artifact referenced by the lane rows I checked exists on disk — the
  ledger does not cite a bench file that is missing.
- The one disagreement: the newest lane's artifact (16:12) and its code edits (15:47–16:04)
  post-date the **CHANGELOG's last write (14:58)** and the changelog-truth artifact
  (14:59) — so **bench and code agree, and the CHANGELOG does not**. That is F1.
- No bench file is overwritten in place by a later lane: each new artifact is a new dated
  file, and the two I checked for supersession (`bench/practice_gamification_design_2026-10-19.md`
  §6 vs the shipped behaviour; `bench/changelog_truth_2026-10-20.md` vs the CHANGELOG)
  agree with the tree.

---

## 6. Findings, severity-ranked

**F1 — CHANGELOG release body missing the newest lane. RELEASE BLOCKER (docs).**
The six class files were edited at **15:47–16:04** and `tests/neutral_actions_state.lua` at
**16:12**; `CHANGELOG.md` was last written at **14:58**. The shipped **offer gate**
(`ST.<CLASS>.practice_common_offer_allowed` — `classes/paladin.lua:4671`,
`classes/warrior.lua:4967`, `classes/rogue.lua:3080`, `classes/shaman.lua:4684`,
`classes/hunter.lua:5053`, `classes/druid.lua:4319`, each consumed by the panel at
`paladin:4719` / `warrior:5178` / `rogue:3266` / `shaman:4887` / `hunter:5294` /
`druid:4592`) is **absent from the CHANGELOG** — grepping the release body for "offer"
returns five hits, none of them this rule. The rule is a **user-visible behaviour change**
("an ability may only be offered on a family where it is either a rotation action or a
neutral action" — `bench/class_neutral_family_coverage_2026-10-20.md:17-24`): on Cata and
Mists the panel no longer offers buttons that could only ever be graded wrong. A release
note that omits it misrepresents what shipped. *Fix:* one entry in the release body (or in
a new `## [2.2.0]` section) citing `bench/class_neutral_family_coverage_2026-10-20.md`.
Owner: operator / changelog lane.

**F2 — No package manifest; the naive package is 249 MB. RELEASE BLOCKER (packaging).**
There is no `.pkgmeta`, no build script and no CI; the addon folder **is** the repo root,
so the workshop ships with it. §4.3 gives the manifest and the exclusions. The single
hardest constraint: the code hardcodes `Interface\AddOns\SwedgeTimer\…`, so the zip's top
folder must be named `SwedgeTimer`. Owner: operator.

**F3 — Trail: 4 broken desk records + a structurally untraceable ledger. MEDIUM.**
§5.2's table (`rogue-rotation` missing journal **and** signal; `warrior-desync` and
`progression-audit` missing signals; `rogue-deep`'s signal is invalid JSON) plus the
`reconcile` schema drift and the fact that **no signal format in this workshop records a
dispatch session id**, so 253 of the 258 session-carrying ledger rows are unfalsifiable.
Fixing the signal format to carry the session id (or having the ledger carry the desk name
and the signal's `run_id` instead of the session id) makes the trail machine-checkable for
the first time. Owner: orchestrator.

**F4 — Version still 2.1.1 for a feature wave. MEDIUM.** §1. Recommend **2.2.0**; the
operator owns the call; the mechanics are 8 fields. If the version stays 2.1.1, F1 becomes
mandatory. Owner: operator.

**F5 — The ledger's Status block understates the tree. LOW.**
`desks/journal.md:9-11` says "37 steps" / "38 steps"; the tree is **43 steps / 0 failed**,
and the same line says the CHANGELOG covers only through the SoD-variants wave. Owner:
orchestrator.

**F6 — `workshop.md`'s desk list is a rotted snapshot. LOW.**
78 listed vs **205** desk dirs on disk; 127 unlisted. The file says the lane table is
authoritative, so this is cosmetic — but the one listed desk that has **no journal**
(`rogue-rotation`) is the real gap. Owner: orchestrator.

**F7 — `Media/AddOns` vs `Media/Addons` casing in the shipped paths. LOW.**
`main.lua:326,329,339` vs `classes/paladin.lua:977-1053` / `nextaction_ui.lua:124`. Harmless
on every shipped client platform (Windows and macOS are case-insensitive); noted for
tidiness only.

**F8 — `Media/` bloat: 371 unreferenced files, 183 MiB. LOW as a code matter, HIGH as a
packaging matter.** 229 of the 444 filenames contain a literal backslash and cannot be
addressed by a Windows client at all. Folding this into F2 rather than fixing it in the
tree (the media are harmless, and the operator may want them). Owner: operator (packaging).

### Non-findings (checked, clean)

- Zero orphan `.lua` modules; zero case mismatches; zero missing toc entries; zero
  duplicate toc entries.
- Exactly one cross-flavor load-order divergence, and it is the documented
  `LibClassicSwingTimerAPI` omission.
- Every addon media file referenced by path exists (73/73); the sounds map is 1:1 with
  `Media/Sounds/`.
- All 8 version fields agree; the CHANGELOG's top section agrees with them.
- The harness is green (43/0, luacheck 2/0 in 85 files).
- Every bench artifact cited by a lane row exists on disk.

---

## 7. Method, and what was NOT done

**Read:** all 7 tocs (full text), `main.lua:300-369` + `:5-6`, `CHANGELOG.md` (headings
+ lines 763-894 + the `[2.1.1]` span), `README.md` (all 100 lines), `TESTING.md` (version
mentions), `bench/final_completion_plan_2026-10-19.md` (Phase 9), `bench/lessons.md`,
`bench/release_audit_2026-10-19.md` (the prior audit, for continuity),
`bench/class_neutral_family_coverage_2026-10-20.md` (head),
`workshop.md` (all), `desks/journal.md` (all 326 lines), `tests/run.sh`,
`tests/toc_check.lua` (all), `.gitignore`, `.gitattributes`.

**Executed (read-only):** `bash tests/run.sh` (writes only to a `mktemp -d` scratch dir);
`find`/`ls`/`grep` over the tree; a case-sensitive toc-vs-disk comparison over all 7 × 61
entries; a toc-vs-toc order/set comparison; a media-reference extraction over every
shipped `.lua` with an existence check per reference; a ledger-vs-desk reconciliation over
205 desk dirs and 273 lane rows.

**NOT done (out of scope, by instruction):** no `.lua`, toc, `Libs/`, `docs/swedge/` or
test file was edited; **no git command was run**; no version was bumped; no CHANGELOG
entry was written; no package was built. **Exactly one file was created: this one.**

**Desk journal / signal deliberately NOT written.** The dispatch scopes this lane to one
new file ("edit anything but that one new bench file"), which forbids the `desk-journal`
and `signal-write` writes those skills prescribe. The ledger already carries this lane's
row (`desks/journal.md:294`, session `ses_ea50b69a3ffeho4fG41TPP7VZ1`), so the trail is
unbroken — but **the orchestrator should close the row and, if it wants the desk's own
record, add `desks/release-readiness/journal.md` + a `done` signal** (note that doing so
is what F3 is about: the signal format cannot carry the session id).

**Validation owner: orchestrator.** The code claims above are re-verified by re-running
`bash tests/run.sh`; the packaging claims are verified by building the manifest in §4.3
and loading it in a client.

**UNKNOWN / not verifiable offline:** the exact CurseForge / Wago / WoWInterface project
URLs (the ids are in the tree; the URLs are the operator's to confirm) and the in-client
behaviour of every changelog entry (all marked offline-only).
