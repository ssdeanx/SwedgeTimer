# practice-audit — Journal

## 2026-10-26 — Desk opened (independent audit + fix, pre-in-client test)

- **Purpose:** independent AUDIT + FIX of the practice UI before the operator's in-client
  test. Two frames (top cue strip + practice panel), Start/Stop semantics (strip moves only
  during a fight), XP earned by TIMING graded presses, options "Open Practice Panel" never
  stops, cross-client (Era ids / TBC names + id fallback), every class route, nil-safety,
  layout vs the operator's reference screenshot.
- **Scope:** `practice_ui.lua`, `practice.lua`, `tests/` only. `classes/*.lua` only if a proven
  defect needs a class seam, and then no ids/rotation changes. No AGENTS.md, Libs/, docs,
  version, spell ids. No git.
- **Inputs read before judging (per @bench-read):** AGENTS.md, CAIRN.md, workshop.md
  (lessons 19-23), bench/lessons.md, desks/journal.md tail, bench/practice_timeline_2026-10-25.md,
  desks/audit-practice/journal.md (2026-10-22 release audit priors), the operator's reference
  image (bench/assets/twist_practice_ui.png).
- **Authoritative target (operator 2026-10-26):** top = where practice happens, starts on
  Start Fight, stops on the same button; practice XP from timing presses per graded attempt;
  closing options leaves practice running (only the practice panel X exits); options entry
  "Open Practice Panel"; Era ids incl. SoD, TBC names first + id fallback; all classes.
- **Next step:** read practice_ui.lua / practice.lua seam by seam against each requirement,
  then test, then fix what is actually wrong.

## 2026-10-26 — Audit complete (pre-in-client gate)

- **Worked on:** traced every practice start route end to end (`ui.start` class sim /
  class drill / rotation scenario / drill list), Start/Stop ownership, the progression
  XP path, the options entry points, cross-client art/state calls, and the strip's
  fallbacks. Read the operator's reference image and compared geometry/labels.
- **Findings fixed (12):** the scenario and drill-list routes never opened the top
  strip (F1); starting either mode hid `panel.fight_btn` permanently, removing Start
  Fight for the rest of the login (F2); the drill strip cued APL rows the panel cannot
  press (F3); the sim strip re-admitted other families' APL rows (F4); a drill Start
  Fight did not re-anchor the ruler (F5); a refused re-begin still ran the strip (F6);
  `toggle_fight` named four class session fields (F7); the strip's default with no run
  state was moving (F8); cues without a single spell id rendered blank even for the
  sim's own actions (F9); `ui.open` raw-showed the strip without a schedule (F10); the
  timeline suite's section 7 was dead behind the PASS report (F11); a closed strip
  stayed closed after a drill Start Fight (F12).
- **Deliberate non-fixes:** the strip stays a cadence PREVIEW (the sim grades the
  swing twist; drills grade their own windows — a real schedule needs a class
  `practice_panel.upcoming` provider); 8/14 paladin APL cues still have no art source
  (per-family id maps, no `spell_id`); 600 px / 24 px geometry is the ported archive
  scale (widening risks panel overlap and invalidates the pinned 75 px/s); no fake
  scrollbar (the strip's 12 pooled icons ARE the window; the log has the scrollbar);
  the reference's "(Reset)" link is absent (panel height pinned; drill classes would
  get unusable paladin binds); drill panels have no Timeline button (the strip is
  already always on).
- **Evidence:** report `bench/practice_audit_2026-10-26.md`. `practice_ui_state`
  2691 checks (was 2626), `practice_timeline_state` 143 (was 128 with 5 dead),
  `bash tests/run.sh` **53 steps / 0 failed**, luacheck 2 warnings / 0 errors in 95
  files. 13 mutations on a `/tmp/opencode` copy (without Media/docs/.git), 13 killed,
  copy deleted. No ids added/removed; `option_tables.lua`, classes, Libs, docs,
  versions and AGENTS.md untouched. LF preserved.
- **Current state:** tree green, awaiting the operator's in-client test.
- **Next step:** operator in-client checklist in report §E (especially: the strip must
  not move before Start Fight; Stop freezes; Start restarts 0:00; options keep the
  session alive; XP only on timed presses; decide on the blank APL cues + scale).
- [signal:done] audit + fixes complete: 12 findings fixed, 13/13 mutations killed, full suite 53/0. Journal marker filed.

## 2026-10-26 — Follow-up: fightless-route strip clock + options re-verify

- **Gap covered:** `scenario_start_session` and `drill_list_start_session` open both
  frames; their strip clock is decided and documented as the **SESSION clock**
  (anchored at the session second, live for the whole run, stopped by the session
  stop). This supersedes the first cut's "opens stopped" choice; pins 32a/32b now
  assert `playhead_running == true`, `origin == session second`, `frozen_at == nil`
  and 75 px/s travel, plus stop hiding both.
- **Related clock fix (F13):** a real-combat pause now shifts `playhead_origin`, and
  `playhead_anchor` uses that shifted anchor (not the raw `sim.fight_start_time`), so
  the ruler/cues do not jump by the pause; section 4 pins anchor 0 -> 5 and the
  ruler reading `0:10` after a 5 s pause. The helper's `running and nil or now` idiom
  was replaced with an explicit branch (it stamped `frozen_at` on running sessions).
- **Options re-verified:** all six class pages + the top-level Practice page read
  "Open Practice Panel" when active (`option_tables.lua:702-720`, 3006, 4236, 4891,
  5464, 6053, 6775; the six class pages pinned by
  `tests/options_load_state.lua:2720-2778`), the desc carries the same guarantee on all seven
  ("closing options leaves the session running; only the practice panel's X stops
  it"; the top-level one also names the /st alias), and `func` calls `practice_ui.open(ST)` — never `stop`; `toggle` is only the
  half-loaded fallback.
- **Evidence:** `practice_ui_state` 2697 (was 2691), `practice_timeline_state` 143,
  `options_load_state` 3612, full `bash tests/run.sh` **53 steps / 0 failed**,
  luacheck 2/0 in 95 files. 17 mutations on a fresh `/tmp/opencode` copy, 17 killed,
  copy deleted. Report updated in place (`bench/practice_audit_2026-10-26.md`).
- **Next step:** unchanged operator in-client checklist; item 4 now expects the
  scenario/drill-list strip to RUN on the session clock.
- [signal:checkpoint] fightless-route session clock + options re-verify complete; suite 53/0.
- Addendum (same follow-up): the options verification is now PINNED too — the G3 loop
  checks each class page's desc names the panel X as the only stop and its func never
  calls `stop` (a `stops == 0` counter); `options_load_state` 3618 checks, 0 failed.
  A desc-stripping mutation kills all six class-page pins. Mutation total 18/18.
