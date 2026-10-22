# workshop

SwedgeTimer's workshop — the place where the desks work. The operating
mechanics are in `AGENTS.md`; this file is the map.

## where the state lives

- lanes, decisions, session ids: `desks/journal.md` (the central ledger)
- open questions and verdicts: `hands-up.md`
- briefs, findings, lessons: `bench/` (`bench/briefs/`, `bench/lessons.md`)
- the last session's honest state: `bench/swing_wire_status_2026-10-21.md`
- the operator's rules: `CAIRN.md` (disposition), `AGENTS.md` (mechanics)

## the rooms

| room | what it is |
|------|------------|
| `desks/` | where desks work — one directory per desk: `desks/<name>/journal.md` (the desk's memory, opened per `desk-open`) and `desks/<name>/.signals/` (structured JSON signals per `signal-write`). `desks/journal.md` is the orchestrator's central lane ledger |
| `bench/` | the shared results workspace. PRIMARY location for cross-desk artifacts: findings, verdicts, drafts, reports land here as dated, named files; supersede loudly, never overwrite. `bench/briefs/` holds dispatch briefs, `bench/lessons.md` holds earned lessons. Desk-local dirs are secondary |
| `hands-up.md` | the escalation ledger — open disagreements become rows here; the operator rules |
| `AGENTS.md` | operational mechanics: conventions, gotchas, cross-engine rules, research tooling |
| `README.md` | the repo map — the addon readme plus the repository map (rooms, toc flavours, where the workshop files live) |

## how work flows

1. the brief is written to `bench/briefs/` — verified paths and ids
   only (verify before you reference).
2. the desk is dispatched; its row goes into `desks/journal.md` with the
   session id exactly as returned by the dispatch.
3. its desk is opened (`desk-open`) and the desk reads (`bench-read`: its own journal (`desks/<name>/journal.md`) to load
   priors, then the bench), works at its desk, holds scope, leaves findings on the bench,
   and emits signals (`signal-write`: hands-up / blocked / done /
   checkpoint) into its `.signals/` directory as it goes.
4. disagreements that can't be settled against external facts become rows
   in `hands-up.md` (and an `escalation/hands-up` signal).
5. the desk ends by journaling (per `desk-journal`): what was done,
   current state, next step — written for someone starting from zero.
6. the orchestrator reconciles: updates the central journal, keeps
   `hands-up.md` in sync (writes back verdicts, moves resolved rows into
   the resolved table), files the residuals, and hands the operator the
   copy list. the operator rules on hands-ups and decides what becomes
   memory.
7. the operator copies the listed files into the client folder and tests
   there. the in-client result is the only proof that counts, it is
   recorded in the journal, and a fix that never reached the folder is not
   a fix (lesson 14).

## current desks

The desk list below is a **snapshot for orientation only** — the central lane table
(state + session ids) in `desks/journal.md` is the only authoritative lane table.
Verified against the tree on **2026-10-21**.

`audit-fixes`, `bar-texture-default`, `bars-design`, `bars-print-policy`,
`bars-reconcile`, `changelog`, `changelog-pd`, `changelog-truth`,
`class-activation`, `class-common-actions`, `class-drills-spec`,
`class-f4-latch`, `class-hold-statements`, `class-isolation`,
`class-isolation-shared`, `class-matrix`, `class-mirror`,
`class-neutral-actions`, `class-neutral-family-coverage`,
`class-neutral-hunter-druid`, `class-order-parity`, `class-stubs-fix`,
`closure-triad`, `compat-audit-fixes`, `compat-bl`, `compat-f4`, `compat-m3`,
`compat-probes`, `compat-tbc-defects`, `competitor-gaps`, `competitor-scan`,
`corpus-corrections`, `design-mode-ux`, `designer-templates`, `diag`,
`display-gaps`, `docs-auditwave`, `docs-truth`, `docstruth-audit`,
`drill-pick-contract`, `druid`, `druid-apl`, `druid-drills`, `druid-hold-ride`,
`druid-paladin-gaps`, `druid-practice`, `druid-rotfix`, `druid-wolfshead`,
`enemy-swing`, `f10-shared-guard`, `filed-closure-sweep`, `final-gate-fixes`,
`final-gate-tests`, `firecrawl-tooltest`, `five-class-gaps`, `fix-engine`,
`fix-guides`, `font-remainder`, `font-sweep`, `gamification-visibility`,
`grader-seam`, `guide-design`, `guide-hud-behaviour`, `hardening-pd`, `hud`,
`hud-guide-gaps`, `hud-slot-pins`, `hud-styles-build`, `hud-templates`,
`hunter`, `hunter-apl`, `hunter-deep`, `hunter-drills`, `hunter-final`,
`hunter-followups`, `hunter-gaps`, `hunter-h2-cut`, `hunter-hud-family`,
`hunter-postpd`, `hunter-practice-designer`, `hunter-proctor-fixes`,
`hunter-resweep`, `hunter-rotation`, `hunter-rotfix`, `hunter-seam`,
`hunter-serpent`, `hunter-sod-build`, `hunter-steady-family`,
`hunter-utility-live`, `hunter-wa`, `hunter-wa-leftovers`, `hunter-weave-prog`,
`icd-tracker`, `ids-research`, `open-rules`, `options`, `options-hooks`,
`options-pass`, `options-sod-fix`, `options-wire`, `oracle`, `oracle-fixes`,
`paladin`, `paladin-apl`, `paladin-audit-close`, `paladin-fixes`,
`paladin-followups`, `paladin-forever-ids`, `paladin-hud-band`,
`paladin-practice-contract`, `paladin-practice-designer`, `paladin-rotation`,
`paladin-scenario`, `paladin-styles`, `paladin-warrior-eratbc`,
`perclient-api-truth`, `perclient-gaps`, `perclient-truth-final`, `practice`,
`practice-coverage`, `practice-gamification`, `practice-hook`,
`practice-neutral-actions`, `practice-nostart`, `practice-persist`,
`practice-progress-ui`, `practice-scenario-engine`, `practice-ui-fixes`,
`prepull-contract`, `print-policy-tail`, `proctor-postpd`, `progression-audit`,
`progression-callsites`, `progression-fix`, `progression-ui-fixes`,
`publish-gate-pins`, `range-api-matrix`, `range-engine-tbc`, `range-lrc-guard`, `readme-pass`,
`reaudit-fixes`, `reconcile`, `reconcile-pd`, `release`, `release-audit`,
`release-docs`, `resolver-callers`, `rogue-apl`, `rogue-apl-reads`,
`rogue-auditfixes`, `rogue-compat`, `rogue-cues`, `rogue-deep`, `rogue-diag`,
`rogue-docs`, `rogue-drills`, `rogue-ema`, `rogue-erroraudit`, `rogue-gcd`,
`rogue-h6`, `rogue-hemorrhage`, `rogue-hunter-eratbc`, `rogue-isolation`,
`rogue-leftovers`, `rogue-nameid`, `rogue-options`, `rogue-parity`, `rogue-pd`,
`rogue-practice`, `rogue-pure`, `rogue-readiness`, `rogue-redzone`,
`rogue-research`, `rogue-rotation`, `rogue-rotfix`, `rogue-shortcd`,
`rogue-skeleton`, `rogue-styles`, `rotation-gap`, `settings-build`, `shaman`,
`shaman-apl`, `shaman-coe-ss`, `shaman-drills`, `shaman-druid-livegate`,
`shaman-druid-nameid`, `shaman-family-scope`, `shaman-g1`, `shaman-icd`,
`shaman-residuals`, `shaman-rotation`, `shaman-rotation-fix`,
`shaman-slot-options`, `shaman-slots`, `shared-engine-bs8`, `sim-resources`,
`sod-detect`, `sod-practice-font`, `stale-claims`, `superseded-wrappers`,
`swing-guard`, `templates-design`, `trinket-usable`, `version-bump`,
`w2-hunter-badges`, `warrior`, `warrior-apl`, `warrior-desync`,
`warrior-drills`, `warrior-hamstring-slot`, `warrior-hold`, `warrior-hs-queue`,
`warrior-rotation`, `warrior-rotfix`, `warrior-styles`, `warrior-utility-live`,
`warrior-utility-residuals`, `weakaura-reverify`, `weakaura-templates`,
`wiring`, `wrath-sod-variants`

## what we learned (the traps that cost us time)

The full ledger is `bench/lessons.md` — newest last. These are the ones that bite
hardest, written for a desk that has never seen this tree:

1. **A pcall unpack is counted by NAMES, not by expected values.**
   `pcall(f, …)` yields status + f's returns; an 8-name list over a 7-return API is
   correct (8 = 1 + 7). An audit miscounted it as an off-by-one and would have
   "fixed" correct code. **When an audit contradicts the harness, run the one suite
   it names before dispatching a fix.**
2. **A citation's line number is a claim.** Fetch the file, cite the verified lines,
   and file the inherited citation for correction instead of copying it.
3. **A 404 is a probe error until the path is checked.** The wowsims org is `wowsims`,
   not `wago-io/wowsims`; `raw.githubusercontent.com/wowsims/classic/master/sim/core/rage.go`
   answers. The strongest id evidence is still the CLIENT's own data
   (`/home/sam/wow.export` = the 1.15.9 SoD client) and warcraftdb per-expansion domains.
4. **ast-grep sees what read/grep cannot.** `read`/`grep` on `/home/sam/wow-ui-source`
   return `permission.rejected: external_directory`; `ast_grep_search` traverses it
   fine. A report saying "the reference repo is unreadable" is a tool-choice mistake.
   (It cannot see a string literal inside a table constructor — that is how a true
   citation got "refuted" once.)
5. **One writer per file — including `tests/run.sh` and the TOCs.** A lane that needs a
   pin in a file another lane owns FILES the pin, it does not edit the file.
6. **The Lua 5.1 local ceiling is a LOAD failure, not a test failure.** 200 file-scope
   locals per chunk; one more `local` and the file does not load, on every client. New
   state goes on the module table (`ST.<CLASS>.*` / `ui.*`), never a file-scope local.
   `classes/paladin.lua` and `classes/warrior.lua` reached 200/200; `classes/shaman.lua`
   and `practice_ui.lua` sit at 199.
7. **Offer only what can be right.** An ability may only be offered on a family where it
   is rotation-ranked or neutral — a button that can only be a mis-pick is a trap. The
   offer gate, the closed-list test and the grader must normalise the class's alias key
   space the same way, or a correct press grades F.
8. **A hold is a decision; unknown is not.** A class states its holds explicitly
   (`{ action = nil, hold = true }`), because "the guide wants nothing" and "the guide
   could not decide" are different facts — and one of them must be able to punish a
   wrong press. A neutral action records no attempt, so idling cannot farm points.
9. **A rotation is the APL's SPELL rows; pre-pull rows live in their own table.** Every
   APL also carries sim-harness rows (trinkets, potions) — those are not rotation
   decisions. And a rotation that only carries the damage abilities is not the class's
   rotation: the utility layer (stances, shouts, rage builders) belongs in the table.
10. **The version is the operator's call.** 2.1.1 stays 2.1.1; a lane recommending a
    semver bump is proposing, not deciding.

11. **A stubbed engine hides the engine's wire.** The offline suites stubbed the
    swing library, so a real library contract — the classic lib's legacy re-fire
    leads with the unit id — was invisible to every suite and the defect shipped.
    A proof for an engine contract runs the REAL vendored library, not a fixture
    that answers in the shape the caller wants.
12. **A dispatcher that shifts one argument fails silently — and it takes every bar
    with it.** The operator's finding (2026-10-21): no swing bar works, not just the
    ranged one — mainhand and offhand are dead for EVERY class. The handler lookup
    missed, the unknown-hand guard printed one line, and every bar sat frozen at its
    init seed with no error and no stack trace. A callback's argument shape is a
    contract: read the engine's fire site, not the handler's signature. When one
    shape is wrong, assume the whole channel is wrong, not one feature.
13. **An options `sorting` member is a key array, not a comparator.**
    AceConfigDialog calls `sorting(info)` and expects the ordered key array back;
    a two-argument comparator receives `(info, nil)` and throws the moment the
    options panel opens. A widget member's contract is the consumer's call shape.
14. **The operator's AddOns folder is the client.** A fix that is not in the
    folder the operator tests from is not a fix — the tree can be green while the
    client runs the old file. Verify the copy, not the tree.
15. **Desk the code.** The orchestrator's own edit is not a desk's trail: no brief,
    no desk journal, no signal, no bench artifact. Two of this session's fixes
    were written by the orchestrator instead of a desk, and the trail shows the
    gap. Code fixes go through a desk; the orchestrator briefs it and reconciles
    it. (Operator correction, 2026-10-21.)
