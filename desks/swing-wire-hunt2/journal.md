# swing-wire-hunt2 — Journal

Read-only hunt. Brief: `bench/briefs/brief_swing-wire-hunt2_2026-10-22.md`.
First dispatch (deleg_780387bd) stopped by operator, interrupted, no report.
Second dispatch (deleg_f6face31) completed; report below filed by orchestrator.
`ast_grep_search` absent from hunter catalog — used `search_files` in-repo and
over `/home/sam/wow-ui-source` (verified working on `classic_era`) + read-only
terminal inspection (one accidental read-only `git branch --show-current`,
no state change). No `Libs/` change proposed (HU-29 stands). No fixed/working
language for unproven items, per operator rule.

## 2026-10-22 — Report filed (read-only, no tree changes)

- **Worked on:** per-client end-to-end hop trace (TOC → lib scope → name gate →
  PEW → INFO_INITIALIZED → init gating → reg object → CLEU → re-fire →
  dispatcher → handlers → bar state → OnUpdate) for Era / Anniversary / Wrath /
  expected-dead paths; ranked defects D8+; HU-25 harness spec.
- **Current state:** Era WIRED at every hop in-tree; Anniversary WIRED except
  conditional-ranged (D2); Wrath gate project-half confirmed, rest UNVERIFIED.
  Ranked explanations for the Era+Anniversary-total report: D10 stale-copy
  first, D8-trigger second, D2 third (ranged-only). Raw transcript:
  `/home/sam/.hermes/profiles/orchestrator/cache/delegation/live/deleg_f6face31/task-0.log`.

### Hop verdicts

- ERA (`SwedgeTimer_Vanilla.toc` 11509): all 13 hops WIRED. No sufficient
  in-tree cause for total death with the strip live. (TOC order, `isClassic`
  TRUE + tables filled `lib:850-966`, name gate passes whenever the addon
  loads — Q1 CLOSED, registry symmetric v7 function-callbacks — Q4 CLOSED,
  CLEU incl. `CAST_START`/`FAILED_QUIET`/`SUCCEEDED(75)`/autorepeat, strip,
  speed-first handlers + counters, seeds via dynamic-STL closure,
  OnUpdate installed per hand, defaults ON `config_presets.lua:127-133`.)
- ANNIVERSARY (`SwedgeTimer_TBC.toc` 20506): hops 1,3–7,9–13 WIRED in-tree
  (client behavior UNVERIFIED); hop 2 diverges (`isBCC` expansion half
  UNVERIFIED — U2); hop 8 MELEE WIRED / RANGED BROKEN-conditional (D2).
  Total death NOT explained by D2.
- WRATH (`SwedgeTimer_Wrath.toc` 38002): TOC WIRED; `isWrath` project half
  orchestrator-confirmed (`WOW_PROJECT_ID = WOW_PROJECT_WRATH_CLASSIC` on
  `origin/classic_titan`); rest UNVERIFIED (U-W1).
- Expected-dead (D7, confirmed): Cata/Mists ship NO lib (verified) → stub →
  `engine_dead` + notice; Retail no lib + `swing_source.available=false`;
  Forever in-tree WIRED post-build (probe-gated frame, speed-first Fire,
  nil idle, unit-less INFO_INITIALIZED), in-client proof owed.
  Base TOC advertises classic-line only (audit F6 holds).

### Ranked defects (D1–D7 stand)

- D8 — BROKEN latent (every lib client + Forever): deadline-first stub
  substitution is permanent and silent. 5 s deadline swaps
  `STL:=make_swing_stub()` + forces `stl_ready` (`main.lua:404-409`) →
  once-gate puts the six regs on the stub no-op (`main.lua:21,770-777`) →
  no re-registration path (single call site `:736`) → late
  `INFO_INITIALIZED` sets an already-true flag. Symptom if triggered:
  "unavailable" notice + dim `engine_dead` + `engine=inert-standin
  deadline=fired` + `swing_*` zeros. No evidence of spontaneous fire.
  Fix: app-side only — late-INFO rewire (re-point STL + re-register under
  double-reg guard) or `needs_rewire` flag instead of swapping STL.
- D9 — DEGRADED (D2 restated): Anniversary-ranged-only death if `isBCC`
  misses. HU-29-blocked; no clean app-side workaround.
- D10 — most-likely explanation of the CURRENT report (deployment, not
  code): stale client copy. Session closed 2026-10-21 with nothing copied;
  Era/Anniversary are separate folders; pre-strip symptom matches exactly
  incl. Anniversary melee (D2 cannot explain it) and Era-total (no in-tree
  cause). Fix direction: copy the listed files; zero code change.
  NOT closable offline (U-H8).
- Q2 ordering: lib-first live; LRC-late live with `lrc=fallback`;
  STL-late = D8 dead forever; no-engine = stub by design.
- Q3: `lrc_ready` ← LRC `CHECKERS_CHANGED` (Era WIRED, Anniversary U-H7);
  `stl_ready` ← INFO_INITIALIZED.
- Q5 bar-side: NO defect — defaults ON, oh/ranged gates nil-safe,
  `activate_class` pcall-closed, range poll cannot hide bars.
- Q6 SST contrast: lib-side single failures → (i) name-gate miss =
  visible error or D8 shape; (ii) `isBCC` miss = ranged-only death;
  (iii) CLEU non-delivery = frozen seed, zero notices/counts;
  (iv) registry miss = silent v7 no-op. Only (iii)-total or D8-total fit
  the report; neither has in-tree trigger evidence → D10 leads.

### Harness SPEC (HU-25 route; must FAIL on current tree)

REAL Lua 5.1 sandbox + scripted WoW API/event bus/manual `C_Timer` clock +
LibStub + shipped v7 + real vendored lib + real `main.lua`
init/reg/dispatcher/handler path + `bars.lua` seed/render with stubbed
frames. Legs per profile (Era `WOW_PROJECT_ID=2`; Anniversary `=5` with
`LE_EXPANSION_LEVEL_CURRENT=1` AND `nil` variant): ADDON_LOADED asserts
units; PEW asserts app-observed INFO_INITIALIZED + `stl_ready`; assert six
regs land in the LIB's v7 registry object; CLEU `SWING_DAMAGE` → mh
advances (`engine_dead=false`); `SUCCEEDED(75)`+autorepeat → ranged
(Era). Negative leg: hold INFO past 5 s, run deadline, deliver lib late →
assert STL identity is the lib and bars advance — FAILS today (D8).
Anniversary-nil leg: ranged advances — FAILS today (D2, expected-fail
pending HU-29).

### UNVERIFIED (offline closers only)

U-H1 Era delivery → harness happy-leg. U-H2 Anniversary values →
orchestrator: constants exist on `origin/classic_anniversary`, runtime
value binary — harness both-variants + shipped diag format. U-H3
Anniversary `SUCCEEDED(75)`/`UnitRangedDamage` → orchestrator
FrameXML diff inconclusive (no `UnitRangedDamage` hit in Anniversary
UnitDocumentation.lua) → harness. U-H4 Wrath → project half confirmed
by orchestrator, rest open. U-H5 Forever → orchestrator-confirmed docs
(`PLAYER_SWING(swingDuration, swingType)`, 0/1/2) + 149-check suite +
harness leg. U-H6 LRC on Anniversary → harness. U-H7 Cata/Mists →
accept by design. U-H8 strip-in-folders → NOT closable offline.

### Non-findings + residuals

Q1/Q4 CLOSED; bar-side ON-by-default; STL closure follows reassignment;
v8 never loads; hands nil-safe; range poll safe; fail-closed activation.
Residuals: `lib:getUnit` target-id compare (`lib:257`); `isMists`
self-compare (`lib:46`, harmless); PEW offhand seed copies mainhand
speed; target UNIT_ATTACK_SPEED unfiltered (noisy); HU-27 landed
exact-yards verified; HU-28 keep v7 (registry trace sufficient).

- **Next step:** builder lane: (1) HU-25 harness per this spec (red on D8
  + D2 legs first), (2) D8 app-side rewire. Then proctor. D10/U-H8 needs
  the operator's folder, no code.
