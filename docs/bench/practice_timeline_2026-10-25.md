# Practice timeline — moving playhead (practice-timeline desk)

Date: 2026-10-25. Desk: `desks/practice-timeline/`. Session: lane of the practice wave.
Operator request (verbatim): "the practice mode doesnt really work. it should be like a
timeline that moves so you know when to click on each ability."

Scope held: `practice_ui.lua`, `practice.lua`, `tests/practice_state.lua`,
`tests/practice_ui_state.lua`, NEW `tests/practice_timeline_state.lua`. Nothing else
was edited (no classes/**, no main/bars/hud/options/config, no TOCs, no run.sh, no docs).

---

## A) Diagnosis — why practice "doesn't really work"

Traced the live start path end to end: `/st practice` → `main.lua:2798-2800`
(`st.practice_ui.toggle`) → `ui.toggle` (`practice_ui.lua:4290`) → `ui.start`
(:5393) → `practice_mode` (:4326) → `ui.practice_start_drill` (:820) →
`ST[active].practice_panel.session.start` → `ui.begin_drill_session` (:853).

### A1 — Class drills had NO timeline at all (REAL, fixed)

* `ui.begin_drill_session` (:853) ended by showing the panel and the driver
  (:895-896) and never touched the timeline frame or `ui.timeline_visible`.
* The only timeline toggle the panel ever built sits inside the sim-widget block,
  gated by `if practice_class_runs_sim_session() and not ui.practice_class_drill()
  then` (:2115) — so the hunter/shaman/rogue/druid panels had no Timeline button
  (the button itself is at :2200).
* The tick renders the log only when `ui.timeline_visible` (:6047), which stayed
  false for every drill session.

Net effect for the operator's class (hunter): a drill session with a score, a
fight timer and a status line, but **no timeline of any kind**. Fixed by the moving
strip (B), which every session now opens (`begin_drill_session` :891-894,
`ui.start` :5592-5595).

### A2 — The timeline that did exist was a post-fight log (REAL, replaced as default)

* `ui.render_timeline` (:3259) draws each icon at `x = event.time *
  TIMELINE_PPS` (:3294) — `event.time` is the fight-relative time of something
  that ALREADY happened (`st.practice.push_timeline_event`, `practice.lua:466-479`,
  is called from the tick's swing path and from `cast_key`).
* The viewport is then pinned to the newest end: `scrollbar:SetValue(max_scroll)` /
  `SetHorizontalScroll(max_scroll)` whenever `ui.timeline_auto_scroll`
  (:3353-3358). So during a fight the player sees history receding, never an
  upcoming cue.

Verified the brief's archive citation rather than inheriting it: the archived build
`docs/swedge/SwedgeTimer_TBC/practice.lua` has the same renderer at :2246
(`st.practice.render_timeline`) and the same scroll-to-end at :2358-2364. It is the
same log, not a moving playhead — so it was NOT copied.

### A3 — Timeline lanes were the paladin's for every class (REAL, fixed)

`build_timeline` used `pr.TIMELINE_LANES` and `render_timeline` used
`pr.TIMELINE_LANE_INDEX` (practice.lua:128-139) for whatever class was active, so a
hunter session built (and could show) a six-lane paladin log. Lane resolution is now
the ACTIVE class's:

* `ui.timeline_lanes()` (:2919) — `practice_panel.timeline_lanes` → else the twist
  sim's own lanes → else none (a class drill with no published lanes gets **no log
  frame at all**, `build_timeline` :3365-3376).
* `ui.timeline_lane_index()` (:2935) — derived from that same list, cached per
  `ST.active_class` so a class switch re-derives it.
* Lane art prefers `lane.texture` / `lane.spell_id` and only then the sim's id table
  (:3434-3447).

### A4 — Checked and found CORRECT (no change)

* **Fight start/stop for drills.** `ui.start_fight`'s guard
  `or ui.practice_drill_active() == true` (:5745) returns while a drill fight runs,
  and the `practice_drill_running()` branch below (:5754) is exactly the
  "drill exists but its fight is stopped" case — reachable and correct. Verified
  against the hunter provider (`classes/hunter.lua:5676-5748`): start → begin →
  tick → cast → stop all match the shared call shapes
  (`pcall(session.start, self, now, ui, {base_speed=…})` :843-845,
  `pcall(session.tick, self, now, elapsed, ui)` :5960).
* **Panel class routing.** `ui.practice_panel()` reads `ST.active_class` only
  (:697-707); the hunter publishes `drill_key = "hunter_forced_move"` and
  `scenario_key` returns the same key (`classes/hunter.lua:5647-5660`), so the route
  matches and `practice_start_drill` runs. No wrong-class routing found.
* **Sessions tick.** The driver frame is shown in both start paths and hidden on
  stop; the compute throttle (`UPDATE_INTERVAL = 0.05`) only skips the first frame.
* **Real-combat freeze** is by design (`ui.tick` :5897-5912); the strip freezes with
  it (see B).

### A5 — Filed, not fixed (cross-lane / out of scope)

1. **Drill sessions ship with NO keybinds.** `begin_drill_session` resets
   `ui.keybinds = {}` (practice_ui.lua:864), so a hunter session is click-only
   until the player right-clicks each icon. The hint says so ("Click a shot to
   cast"), but a "my keys do nothing" report is plausible. Proposed contract for a
   follow-up class lane: OPTIONAL `practice_panel.default_keybinds = { [key] = "1" }`
   read by `begin_drill_session` instead of the unconditional `{}`. No class
   publishes it today, so wiring it now would be dead code — filed, not built.
2. **`ui.reset_keybinds` applies the paladin defaults to any class**
   (practice_ui.lua:2512-2526 + `pr.DEFAULT_KEYBINDS` practice.lua:113-124). On a
   drill class every default key ("cs", "sob", …) is outside `practice_order()`, so
   `rebind_keys` (:2326-2353, the bind loop at :2343-2351) silently creates nothing while the chat line claims
   "Practice keybinds have been reset." Cosmetic today (the session starts with no
   binds anyway).
3. **`practice_start_drill` swallows a throwing provider's error**
   (practice_ui.lua:843-846): `pcall` keeps `started` only, so the user sees
   "Practice drill is not available (session rejected)." without the reason. A
   diagnosability gap, not a broken path.
4. **`ui.toggle_fight` still special-cases four class session fields**
   (`ui.hunter_session` etc., practice_ui.lua:5721-5731) although
   `ui.practice_drill_active()` gives the same answer generically
   (`update_button` :6577-6580 already uses it). Works today; a new drill class would
   have to add a line.
5. **The strip's rows are fixed at build.** `build_playhead` resolves
   `timeline_lanes` once (init, out of combat). A mid-session class switch (the
   class mirror) keeps the old row count until re-init. The LANE INDEX is
   re-derived per class (:2935), so no event is dropped; only the row layout is
   stale.
6. **The strip is not a design-mode target.** `design_targets.practice_timeline`
   still points at the log frame (:7046-7070 region). Dragging the strip saves the
   same `ui.timeline_x/y`, so design-mode save/reset still moves both; a descriptor
   of its own is an options-lane item if the operator wants it.

---

## B) The moving cue strip (the deliverable)

### Geometry (pure, `practice.lua`)

| helper | line | meaning |
|---|---|---|
| `TL_PLAYHEAD_FRACTION = 0.25` | :504 | playhead at 25% of the visible strip |
| `TL_HORIZON_SECONDS = 6` | :506 | six seconds ahead |
| `timeline_playhead_x(width, frac)` | :525 | playhead x in px (150 on a 600 px strip) |
| `timeline_pps(width, frac, horizon)` | :535 | 75 px/s on a 600 px / 6 s strip |
| `timeline_event_x(px, at, now, pps)` | :550 | `px + (at - now) * pps` — future right, past left |
| `timeline_window(now, w, pps, frac)` | :562 | absolute clock range on screen (2 s back, 6 s ahead) |
| `timeline_slice(events, n, from, to)` | :575 | first/last index inside the window (inclusive, no alloc) |
| `timeline_row_is_cue(row)` | :594 | `live == true and engine == true` |
| `timeline_cadence(out, rot, anchor, now, horizon, gcd, cycle)` | :608 | reusable neutral preview schedule |

With `width=600`, `fraction=0.25`, `horizon=6`: playhead 150 px, 75 px/s, 2 s of
history visible on the left. An icon at `at == now` is ON the playhead. Cues that
have just crossed stay on the strip for those 2 s (press feedback) and leave the
pool when they scroll out.

**Cadence spacing:** a cycle carries `round(cycle/gcd)` cues spread evenly over it,
so 1.5 s GCD inside a 3.5 s cycle = two cues 1.75 s apart, and the cycle repeats
exactly every 3.5 s. This avoids the boundary burst an exact-GCD walk gives
(…, 3.0, 3.5 = two cues half a GCD apart). The schedule is anchored to the
fight/session start — re-anchoring on `now` would pin every cue in place.

### Frame (`practice_ui.lua`)

* `ui.build_playhead` (:3656) — one `BackdropTemplate` frame ("…PracticeCueStrip"),
  title FontString, track texture, a fixed 2 px playhead cursor placed once, and a
  pre-created pool of 12 icon frames + 12 labels (out of combat at init, so no tick
  ever creates a frame). Position shares `ui.timeline_x/y` with the log.
* `ui.playhead_draw` (:3872) — the ONLY per-frame work, on the strip's own
  `OnUpdate` (:3753-3755): slice the schedule for the window, `ClearAllPoints` +
  `SetPoint` the pooled icons, dress newly-changed art (`playhead_dress` :3923,
  latched by spell id/texture), hide the tail. No table allocation, no rebuild, no
  full re-render. Returns early when the strip is hidden or `ui.combat_paused`.
* `ui.playhead_emphasis` (:3936) + `ui.playhead_due` (:3928) — the PRESS cue: an
  action whose second has arrived (from 0.15 s before to 0.25 s after its `at`) is
  lit at full alpha with a gold border; every other cue sits at 0.7 alpha. Latched
  per icon, so a steady state costs two comparisons.
* `ui.playhead_refresh` (:3832) — schedule rebuild, at most every 0.1 s, driven by
  the compute tick (:5940). Gates: session active AND strip shown. Provider asked
  only here.
* `ui.playhead_show` (:3965) — session start: stamps `playhead_origin`, shows the
  strip (unless History is open), primes the schedule.
* `ui.playhead_clear` (:3949) — stop: hides every pooled icon, zeroes the count,
  keeps the slots for reuse.
* History: `ui.toggle_timeline` (:3556) now swaps views in the same spot (open the
  log → hide the strip; close it → restore the strip while a session runs). Panel
  button relabelled "Timeline" → "History" (:2200, `update_timeline_button`
  :3577-3595). Default off.

### Data contract (for the class lanes — the hunter wiring is a follow-up)

Read from the ACTIVE class's `practice_panel` (`ST[ST.active_class].practice_panel`).
Both members are OPTIONAL:

```lua
practice_panel.timeline_lanes = {
    { key = "cast", name = "Cast", texture = "Interface\\Icons\\…" },  -- texture optional
    -- spell_id = <number> is also accepted when there is no texture
}

-- ui = st.practice_ui, now = absolute clock (st.api.get_time()),
-- horizon = seconds the strip can show (6 today)
practice_panel.upcoming = function(ui, now, horizon)
    return {
        { at = <absolute clock>, key = "<action key>", label = "<text>",
          texture = <string|nil>,          -- nil + spell_id resolves through GetSpellInfo
          spell_id = <number|nil>,
          lane = "<lane key>|nil" },      -- a lane key from timeline_lanes, or nil = row 1
        -- ascending by `at`, future events only
    }
end
```

Contract details the shared layer guarantees a provider:

* an event with `at < now` or `at > now + horizon` is dropped (a provider cannot
  inflate the schedule);
* at most 12 cues are kept/drawn (the soonest ones);
* an EMPTY array is authoritative — no icons, no fallback, title unchanged;
* a THROWING provider falls back to the cadence preview (never a blank strip);
* `timeline_title` (optional string) is the strip's own label; the default is
  "Upcoming actions".

**FALLBACK when `upcoming` is absent:** the "Rotation cadence (preview)" strip,
built only from the class's own published tables — `practice_rotation` rows with
`live == true and engine == true`, spaced by `PRACTICE_GCD_SECONDS or 1.5` and
`PRACTICE_CYCLE_SECONDS or 3.5`, anchored to the drill's fight clock (or the
session start). Never another class's rotation, never an invented action name. A
multi-family class shows every published live+engine row in published order — the
label says "preview" because it is a cadence, not the APL's decision order.

**No class table (`ST[active]` nil / no module):** `ui.playhead_available()` is
false, `ui.playhead_show` refuses, the frame stays hidden, and no schedule is built.

---

## C) Tests and proof

Suites (all green, only these three were run — `bash tests/run.sh` is the
orchestrator's):

| suite | result |
|---|---|
| `lua5.1 tests/practice_state.lua` | PASS 1582 checks (was 1533, +49 pure timeline pins) |
| `lua5.1 tests/practice_ui_state.lua` | PASS 2608 checks (was 2542 before this lane; section 16 rewritten for the History default, new section 31 for the strip) |
| `lua5.1 tests/practice_timeline_state.lua` | PASS 102 checks (NEW, self-contained) |

`luacheck` on the five touched files: 0 warnings / 0 errors (the two touched test
files lint clean; the new suite lints clean).

Frame census updated deliberately: `init` creates 83 frames (was 70) = +1 strip
frame +12 pooled cue icons. The pin and its comment are in section 2 of
`tests/practice_ui_state.lua`.

### Mutation proofs (19/19 killed, `/tmp/opencode` copies, copies deleted)

Each mutation was applied to a copy of the tree (rsync without `Media/docs/.git`),
the three suites were run, and the file was restored. `RED` = that suite exits
non-zero; a mutation counts as killed when at least one suite goes red.

| # | mutation | killed by |
|---|---|---|
| M1 | playhead fraction ignored (always mid-strip) | practice RED, practice_timeline RED |
| M2 | event direction flipped (`now - at`) | all three RED |
| M3 | slice upper edge exclusive | practice RED, practice_timeline RED |
| M4 | cadence keeps non-cue rows (`live`/`engine` filter removed) | practice RED, practice_timeline RED |
| M5 | cadence re-anchors on `now` (cues stop moving) | practice RED, practice_timeline RED |
| M6 | cadence cycle ignored (one step per cycle) | practice RED, practice_timeline RED |
| M7 | provider horizon filter dropped | practice_timeline RED |
| M8 | `ui.active` no longer gates the provider | practice_timeline RED |
| M9 | stop-clear leaves the icons up | practice_ui RED, practice_timeline RED |
| M10 | cadence label says "Upcoming actions" | practice_ui RED, practice_timeline RED |
| M11 | History no longer hides the strip | practice_ui RED |
| M12 | drill start never shows the strip | practice_ui RED |
| M13 | sim start never shows the strip | practice_ui RED |
| M14 | past cue clipped at the playhead (`x >= half`) | practice_timeline RED |
| M15 | drill lanes fall back to the paladin lane table | practice_ui RED |
| M16 | the press cue never lights | practice_timeline RED |
| M17 | lane row ignored (every cue on row 1) | practice_timeline RED |
| M18 | cue art never resolves from a spell id | practice_ui RED |
| M19 | schedule rebuild never throttled | practice_ui RED |

### Covered cases requested by the brief

playhead math past/now/future · horizon slicing (inclusive edges, empty, zero
count, nil array, nil bound) · provider present (order, past dropped, horizon
dropped, textures, labels, lanes) · empty provider (authoritative, no fallback) ·
provider absent → cadence fallback (label + spacing + anchor stability + empty /
nil / no-live-row rotations) · class table absent → hidden · off → zero provider
reads · pool reuse (no frame created on a second draw, same slot objects) · session
stop clears (count 0, every icon hidden) · combat pause freezes the strip · one
OnUpdate, inert while hidden.

---

## D) Owed in-client checks (offline cannot prove these)

1. The strip renders on a real client (font path via `st.utils.apply_font`,
   BackdropTemplate, strata HIGH) and its text does not clip its label line.
2. Drag the strip, `/reload`-free, stop/start a session: the strip returns to the
   dragged spot and History opens in the same place.
3. Hunter session: does the cadence preview feel like the right *rhythm* (2 cues
   per 3.5 s cycle at 1.75 s) beside the real Auto Shot cycle? If not, the class
   lane's `upcoming` provider is the fix, not a geometry change.
4. Paladin session: the preview is built from the APL rows; confirm it does not
   fight the next-action guide's HOLD/RIDE (they are separate surfaces).
5. Combat pause: strip freezes and resumes without a jump (the drill's windows
   shift by the pause; the strip's anchor follows `fight_elapsed`).
6. `SetPoint` per frame on up to 12 frames: watch for hitching on the operator's
   client (this is the only per-frame work added).

## E) run.sh line owed (orchestrator owns the file)

```
run "lua5.1 tests/practice_timeline_state.lua" lua5.1 tests/practice_timeline_state.lua
```

`tests/toc_check.lua` currently reports two failures: "every suite on disk is
registered in tests/run.sh" (unregistered: `tests/appearance_defaults_state.lua`,
`tests/engine_matrix_state.lua` — other lanes' new suites — and
`tests/practice_timeline_state.lua`). That is the orchestrator's registration step,
not a suite failure.

---

## F) Follow-up (2026-10-25, orchestrator reconciliation): stale pin re-cut

`tests/rogue_state.lua` pinned the literal `ui.practice_begin_fight(self, api.get_time())`.
The Start Fight drill branch now reads the clock ONCE —
`local drill_now = api.get_time()` (`practice_ui.lua:5784`) — and hands that same value
to `ui.practice_begin_fight(self, drill_now)` (:5785),
`ui.playhead_refresh(self, drill_now, true)` (:5786) and `ui.playhead_draw(drill_now)`
(:5787), so the re-begun run and the strip cannot disagree by a frame. The pin was
stale, not the code; it is re-cut to assert the one clock read plus all three
consumers (`tests/rogue_state.lua:2614-2624`). Proof: `lua5.1 tests/rogue_state.lua`
→ 1137 checks / 0 failures (+3 net checks); three mutations on a `/tmp/opencode` copy
kill it (old literal, a second clock read for the strip, `drill_now` sourced from a
stale field). No production code changed in this follow-up.
