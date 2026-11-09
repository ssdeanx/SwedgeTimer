# Practice UI audit — two frames, Start/Stop, timed XP (2026-10-26)

Desk: `desks/practice-audit/`. Scope held: `practice_ui.lua`, `tests/` only —
`classes/*.lua`, `option_tables.lua`, `Libs/`, docs, versions, AGENTS.md and every
spell id untouched. No git commands. Reference image:
`bench/assets/twist_practice_ui.png` (operator's target).

Verdict: **the two-frame wiring, Start/Stop ownership and the timed-XP path are
sound for every class route, and 13 findings were fixed (12 product defects + one
dead-pin test defect).**
The strip is still a **rotation-cadence preview, not a schedule of the graded
press** — that is the one thing the operator will notice (limits §D1/D2); it needs
a class-published `practice_panel.upcoming` provider, not a shared-layer guess.

## A. Findings (severity, status, evidence)

**F1 HIGH — the scenario and the drill list opened the panel WITHOUT the top strip.**
`scenario_start_session` and `drill_list_start_session` never touched
`playhead_*` and never called `playhead_show`; the strip is hidden at build
(`practice_ui.lua:3969`) and at stop (`:6116`). Fixed: both routes open through
`ui.playhead_session_open` (`:5561`, `:5818`). **Clock decision:** these routes have
no swing fight, so their strip runs on the **SESSION clock**, anchored at the
session second (the session start is their clock) and stopped by the session stop;
the sim/class drills stay fight-gated. Pins: 32a/32b (running, origin, 75 px/s
travel). Mutations M2/M3 (missing) + M14/M15 (clock).

**F2 HIGH — visiting the scenario or the drill list once removed Start Fight for the
rest of the login.** Both routes hide `panel.fight_btn` (`:5546`, `:5803`) and no
path ever re-showed it, so every later class session had no Start/Stop button —
the operator's core rule became unusable. Fixed: `ui.start` re-shows it before the
mode dispatch (`:5852`). Pin: 32a. Mutation M1.

**F3 MED-HIGH — the drill strip cued actions the drill panel cannot press.**
The cadence always read `module.practice_rotation` (the APL table), e.g. the hunter
Era table's Rapid Fire / Serpent beside its three shots, and omitted Steady (the
drill's main shot) entirely. A cue that can never become the graded press is a
trap. Fixed: a class drill previews its own `order` (the panel's pressable set);
the sim path keeps the APL rotation (`:4077-4092`). Pins: 32e + timeline §7.
Mutation M4.

**F4 MED — the sim strip re-admitted another family's APL rows.** The paladin's
full `practice_rotation` carries WotLK-only rows (`hw`, `ds`, `hs`, `am`, `hor`,
`how_wrath`) while the panel vocabulary already uses the family gate
(`ST.PALADIN.practice_rotation_for`, classes/paladin.lua:5496). Fixed: the strip
reads the class's family-gated slice through `ui.practice_rotation_rows` (`:3692`),
falling back to the full table on a missing/empty/throwing slice. Pin: timeline §9.
Mutations M11/M12.

**F5 MED — Start Fight re-began a drill fight without re-anchoring the ruler.**
After Stop→Start the cue cadence re-anchored (via `fight_elapsed`) but
`playhead_origin` kept the old session second, so the ruler showed 0:42 while the
cues restarted at 0:00. Fixed: `ui.playhead_origin = drill_now` (`:6214`). Pin:
32c. Mutation M5.

**F6 MED — the strip could animate with no fight.** `start_fight` set
`playhead_running = true` before calling the provider; a silently refusing `begin`
left the cues moving on a stopped session (violates "moves only while a fight
runs"). Fixed: verify `practice_drill_active()` after the begin and freeze
otherwise (`:6206-6212`), no new notice (the existing silent-no-op pin at
tests/practice_ui_state.lua:2276-2278 holds). Pin: 32d. Mutation M6.

**F7 MED — the Start/Stop button named four class fields.** `toggle_fight` read
`ui.hunter_session` / `shaman` / `rogue` / `druid` (`:6153`); a class drill whose
run state lives anywhere else leaves the button dead (label says Stop, press does
nothing). Fixed: use `ui.practice_drill_active()` — the same seam
`update_button` already reads — with the sim as the fallback. Pin: 32c (button
path). Mutation M10.

**F8 MED — the strip's default with no run state was MOVING.** `playhead_draw`
only froze when `frozen_at` was set; a route that forgot the flags animated on the
live clock. Fixed: `playhead_show` latches a frozen stamp when no run is claimed
(`:4361-4363`). Pin: timeline §8. Mutation M7.

**F9 LOW-MED — cues with no single `spell_id` rendered blank boxes even for the
sim's own actions.** The paladin rotation rows carry per-family id maps, not a
`spell_id`, so judge / consec / soc / sob / sotc had no art. Fixed: the sim route
falls back to the panel's own ability art (`:4300-4306`, sim only — never the
paladin's table on a drill class). Pin: 32a. Mutation M8. Residual §D2.

**F10 LOW-MED — `ui.open` raw-showed the strip without rebuilding its schedule.**
A cleared schedule would show a blank strip from the options entry. Fixed: open
goes through `playhead_show` (`:4709-4721`). Pin: 32a. Mutation M9.

**F11 LOW — dead pins in the timeline suite.** `tests/practice_timeline_state.lua`
section 7 sat AFTER the PASS/FAIL report, so its checks (the class-order cadence)
could fail while the suite printed PASS and exited 0. Fixed: report moved last;
section 7 is live again (134 checks at that point, was 128 with 5 dead; the file now finishes at 143 after the new sections). Mutation M4 now makes it red.

**F12 LOW — a strip closed with its X stayed closed for the whole drill session.**
The sim path re-showed it on Start Fight; the drill path did not. Fixed with F5's
block (`:6218-6221`). Pin: 32c. Mutation M13.

**F13 LOW-MED — a real-combat pause jumped the strip's clock.** The sim/drill clocks
shifted on resume but `playhead_origin` (the ruler's zero, and the cadence anchor for
the fightless routes) did not, so the ruler jumped by the pause and the sim cadence
re-anchored on the unshifted `fight_start_time`; the session anchor also carried a
stale frozen stamp while running (the `running and nil or now` idiom evaluates to
`now` for `true`). Fixed: the pause shifts `playhead_origin`
(`practice_ui.lua:6402-6409`), `playhead_anchor` uses that shifted anchor
(`:4012-4027`), and `playhead_session_open` clears the stamp explicitly
(`:4379-4391`). Pin: section 4 "pause: the strip anchor shifts by the pause" +
the ruler reads `0:10` at resume. Mutations M16/M17.

**Verified held, no defect (and the pin):**
- **Panel X is the only panel-side exit** (`practice_ui.lua:2006-2010`); `/st
  practice` toggles start/stop (`main.lua:2810-2814`);
  tests/practice_ui_state.lua:1480-1529 pin both, plus "a second stop is a silent
  no-op".
- **Options "Open Practice Panel"** on all six class pages: name while active,
  desc, `open` preferred and `toggle` never called when `open` exists —
  tests/options_load_state.lua:2712-2785 (G3; the loop also pins the desc guarantee
  and a `stops == 0` counter around the func). Closing AceConfig has no stop hook
  anywhere (grep: no `OnClose`/`CloseSpecialWindows` in option_tables.lua).
- **`ui.open` never stops** and re-raises a hidden panel / restarts a stopped
  trainer: tests/practice_ui_state.lua:1536-1544, plus 32a for the strip.
- **XP only from graded presses**: opening/closing earns 0, an idle running fight
  earns 0, one timed twist earns — pin 32f. The completion bonus is a share of
  earned XP and a zero-attempt session pays nothing
  (practice_progress.lua `P.end_session`; tests/practice_progress_state.lua:526-530).
- **Both frames on all six class routes**: paladin sim §31 + 32a; hunter §31
  (7723-7724); shaman 3816-3817; rogue 3632-3633; druid 3887-3888; warrior drill
  list 5047-5048.
- **Fallbacks**: absent panel (timeline §4 "no class table"), absent rotation
  (§7 order fallback), absent/throwing `upcoming` (§4), no class table, combat
  pause, pool reuse, stop-clear, pre-init nil hooks (practice_ui_state §10 HOOKS).
- **No state query was added or changed.** `practice_ui.lua` contains no
  `GetSpellCooldown` / `IsSpellKnown` / `GetSpellPowerCost` call; the only spell
  APIs are art (`api.GetSpellInfo`, `GetSpellTexture`) at `:341-348`, `:777-786`,
  `:1747-1754`. No id was added, removed or re-pointed in this audit.

## B. Files changed

| file | change |
|---|---|
| `practice_ui.lua` | `ui.playhead_session_open` (`:4379`), `ui.practice_rotation_rows` (`:3692`), the start/stop fixes (`:6193-6221`), the pause anchor shift (`:6402-6409`), `toggle_fight` (`:6153`), `playhead_show` latch (`:4344`), cadence source (`:4076-4094`), art fallback (`:4270-4306`), `ui.open` (`:4709`), fight-button restore (`:5863`), route opens (`:898`, `:5561`, `:5818`, `:6033`) |
| `tests/practice_ui_state.lua` | +71 checks: section 32 (routes/frames/stop/start/art/open/XP), strip pins in the hunter/shaman/rogue/druid/warrior blocks, three false "session opens stopped" comments for drill fixtures corrected |
| `tests/options_load_state.lua` | +6 desc checks (all six class pages) and a `stops == 0` counter in the G3 "prefers open" pin |
| `tests/practice_timeline_state.lua` | report moved last (dead pins revived), §7 drill-order pin, §8 no-run-state freeze pin, §9 family-gated slice pin; fixture `make_strip` states a running session |

Line endings preserved (all three files are LF; 0 CR lines). No new file-scope
locals (`practice_ui.lua` 171 locals, limit 190).

## C. Tests

| suite | result |
|---|---|
| `tests/practice_ui_state.lua` | PASS **2697** checks (was 2626) |
| `tests/practice_timeline_state.lua` | PASS **143** checks (was 128, with 5 dead) |
| `tests/practice_state.lua` | PASS 1582 |
| `tests/practice_progress_state.lua` / `_stats_` / `_progress_ui_` | 494 / 558 / 290, 0 failed |
| `tests/paladin_state.lua`, `hunter_state`, `shaman_state`, `rogue_state`, `druid_state`, `warrior_state` | 1270 / 1831 / 1083 / 1137 / 1621 / 2098, 0 failed |
| `tests/options_load_state.lua` | 3618, 0 failed |
| `bash tests/run.sh` | **53 steps, 0 failed**; luacheck 2 warnings / 0 errors in 95 files |

### Mutation proofs (18/18 killed; `/tmp/opencode` copy without Media/docs/.git, deleted after)

| # | mutation | killed by |
|---|---|---|
| M1 | remove the fight-button restore | 32a Start Fight restore |
| M2 | drop the scenario strip open | 32a strip shown (+ hard abort on the nil schedule) |
| M3 | drop the drill-list strip open | 32b strip shown |
| M4 | drill cadence back to the APL table | 32e + timeline §7 (live again) |
| M5 | drop the drill `playhead_origin` re-anchor | 32c ruler 0:00 |
| M6 | drop the refused-begin freeze | 32d strip stopped |
| M7 | drop the `playhead_show` freeze latch | timeline §8 |
| M8 | drop the sim ability-art fallback | 32a Judgement art |
| M9 | `ui.open` raw `Show` (no schedule rebuild) | 32a schedule rebuilt |
| M10 | `toggle_fight` back to sim-only | 32c button Stop |
| M11 | ignore the family-gated slice | timeline §9 gated row |
| M12 | un-pcall the slice probe | timeline suite aborts (throwing provider) |
| M13 | drop the closed-strip re-show | 32c closed strip returns |
| M14 | scenario strip clock back to stopped | 32a session clock |
| M15 | drill-list strip clock back to stopped | warrior/32b session clock |
| M16 | drop the pause anchor shift | section 4 anchor pin |
| M17 | cadence anchor back to `fight_start_time` | section 4 cadence pin |
| M18 | remove the panel-X guarantee from the descs | G3 desc pin x6 |

## D. Deliberate non-fixes / residual limits (read before testing)

1. **The strip is a cadence preview, not the graded press schedule.** Paladin: the
   sim grades the twist at swing landing (weapon speed + haste), while the cues
   cycle the APL at a fixed 1.5 s GCD / 3.5 s cycle. Drills: cues are the panel's
   pressable order on the same cadence, not the forced-move / weave / pool window.
   The class contract already supports a real schedule
   (`practice_panel.upcoming` + `timeline_lanes`, `practice_ui.lua:3599-3626`);
   no class publishes one. Inventing a rotation was out of scope.
2. **8 of the paladin's 14 live+engine APL rows still have no art source** (`exo`,
   `how`, `hw`, `ds`, `hs`, `am`, `hor`, `how_wrath`): the rows carry per-family
   id maps (`ids`) + `tbc_name`, not a `spell_id`, and have no sim ability. They
   render as bordered boxes. A cached family-id art resolver or a class-published
   cue texture is the follow-up; adding/researching ids here is forbidden
   (standing rule).
3. **Layout scale differs from the reference.** The strip is 676 px wide (600 px
   track + rail), 24 px rows, `TIMELINE_DEFAULT_Y = 260`; the reference's timeline
   spans nearly the full screen with larger rows. Not changed: it is the archive
   geometry the prior desk ported and the pinned playhead scale (75 px/s at 600 px)
   depends on it; widening risks overlapping the panel on a user bar layout and
   needs an in-client measurement. A width change is one constant + re-pin if the
   operator wants it.
4. **No scrollbar on the strip** (documented, not faked): the strip is a fixed 6 s
   window over a generated schedule; its 12 pooled icons ARE the visible window,
   so there is no off-screen history to scroll. The scrollable frame is the
   post-fight log (`ui.timeline_frame`, built with a scrollbar at `:3485-3490`), still
   reachable from the paladin panel's History button.
5. **The reference's "(Reset)" link is absent.** `ui.reset_keybinds` exists but is
   unreachable; wiring it needs a new clickable row (panel height 370 is pinned)
   and on the four drill classes it would write paladin default keybinds the drill
   cannot use. Not one of the binding requirements; filed.
6. **The drill panels have no Timeline/History button** (the sim has one, labelled
   History). The strip is always on for a session, so a toggle would only hide the
   practice surface. The reference's "Timeline" button opens what is already open.
7. **The strip's title line** ("Rotation cadence (preview)" / a provider's title)
   is not in the reference (empty there). Kept deliberately: it is the only place
   that says the cues are a preview.
8. **Era art gaps (cross-client).** `LANE_SPELL_IDS` / `STEP_SPELL_IDS` /
   `pr.ABILITIES` use fixed ids (CS 35395, SoB 31892). On the Era client (SoD) CS
   is a rune (407676) and SoB is SoD-only, so those rail/cue art slots may be
   blank there; the operator's TBC Anniversary client resolves them. No id was
   added or removed.
9. **A class with drills but no rotation/order/sim has no cue source**; the strip
   stays hidden (`playhead_available` false, pinned). No live class hits it.
10. **The strip's row layout is fixed at build** (a mid-session class switch keeps
    the rows; the lane index re-derives). Pre-existing, filed in
    `bench/practice_timeline_2026-10-25.md` §A5.5.
11. `ui.practice_rotation_rows` calls the class's `practice_rotation_for()` per
    schedule rebuild (~10/s). It allocates a small slice table per rebuild; caching
    would risk a stale order after the live gather resolves. Accepted.

12. **The options label reads "Open Practice Panel" only while a session is active;
    while idle it reads "Start Practice"** (all six class pages are pinned; the
    top-level Practice page carries the same three lines by inspection,
    `option_tables.lua:702-720`). Both labels call `open` (which starts when idle
    and never stops), and tests/options_load_state.lua:2712-2785 pins exactly this
    split (plus the desc and a stop counter). If
    the operator wants the literal string "Open Practice Panel" in BOTH states, it
    is a one-line change per entry in `option_tables.lua` — outside this lane's
    product scope; filed, not changed.

## E. In-client checklist (offline cannot prove these)

1. Paladin: the strip sits at 25% with `0:00` under the playhead and does NOT move
   until Start Fight.
2. Start Fight: cues travel right-to-left; Stop freezes them in place; Start again
   restarts the ruler at `0:00` and the cues from the new fight.
3. Hunter / shaman / rogue / druid: the session opens with its own fight already
   running (button reads Stop Fight) and the strip moving; Stop/Start work.
4. Warrior / scenario / drill-list modes: both frames are present; the strip runs
   on the SESSION clock (no fight clock) and Start Fight is hidden in those modes.
5. Options → Practice → "Open Practice Panel" during a session: practice keeps
   running; closing options does not stop it; the panel X is the only panel exit.
6. XP: open+close with no press = no XP; a timed twist/cast = XP.
7. Visual: confirm whether the blank paladin APL cues (§D2) are acceptable for this
   pass, and whether the 600 px / 24 px scale (§D3) is close enough to the image.
