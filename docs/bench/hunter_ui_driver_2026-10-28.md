# hunter-ui-driver — HU-37 / audit P2 (2026-10-28)

Desk: `hunter-ui-driver`. Brief: `bench/briefs/brief_hunter-ui-driver_2026-10-28.md`.
Verdict: **LANDED — gate green** (54 steps / 0 failed; luacheck 2 warnings / 0 errors in 97
files). Write scope held: **two files**, no TOCs, no docs, no version change (2.1.3), no git.

## Files changed

| file | change | size |
|---|---|---|
| `hunter_ui.lua` | +219 lines: the always-running hunter tick, the configured-visibility gate, layer parity, lazy-badge parents; header/comment corrections | 1668 -> 1887 lines |
| `tests/hunter_state.lua` | +239 lines: sandbox script recording + faithful child frame levels, `tick_host` helper, §14n / §14n-i / §14n-ii, NILSWEEP HU2 re-cut | 6479 -> 6718 lines |

Nothing else was touched. `option_tables.lua`, `diag.lua`, `main.lua`, `power_bar.lua`,
`bars.lua`, `classes/*`, TOCs, `Libs/` all untouched.

## The defect, exactly

`hunter_ui` built the visual set as children of the ranged **bar frame**
(`ranged_state.anchor_frame.bar_frame`) and ticked it only from that frame's `OnUpdate`
(pre-fix `ui.on_bar_update(self, "ranged") -> ui.update`, now
`hunter_ui.lua:1866`). `ST:handle_bar_visibility` (main.lua:2961 at this snapshot) hides that frame for
the in-use hands, and `ST:hide_bar` (main.lua:265-288) calls `bar_frame:Hide()`. A hidden frame
runs no `OnUpdate`, and a hidden parent hides its children, so with Auto Shot not armed and
no shot receipt inside the activity window a Steady Shot / Volley cast painted **nothing**
(also no proc badge, no range helper, no cast zone). `ranged_bar_ready` (hunter_ui.lua:179)
never consulted the activity gate, so the set believed it was ready while nothing could run.

## The fix

1. **The tick rides the hand's anchor frame** (`claim_tick_host`, hunter_ui.lua:308).
   `bars.lua` creates `ranged_state.anchor_frame` as the per-hand top-level frame
   ("the top-level parent of the bar visual frames in our addon", bars.lua:84-92). It is
   shown in `configure_bar_size_and_positions` (bars.lua:611) and **never hidden by the
   visibility path** — `hide_bar` hides only `bar_frame` and `hiding_anchor_frame`
   (main.lua:278-283). The hunter installs its `OnUpdate` on that frame
   (hunter_ui.lua:308-321), so the tick is always eligible.
2. **The widgets parent to the anchor frame** and keep every anchor/width against the
   ranged bar frame (hunter_ui.lua:671-680 and the creators at :452+). A texture cannot
   be re-parented, so the cast zone stays on the bar's visuals frame — its own gate only
   paints inside a live ranged cycle, which always implies the bar is visible for that
   cycle's receipt window, so no set paint is lost (comment at `create_cast_zone`).
   Lazy badges (OOM/LnL/trap) parent to the host too (hunter_ui.lua:1484, :1561, :1640).
3. **Exactly one tick source per frame.** While the ranged bar is visible AND carries its
   `OnUpdate`, the bar tick drives the set exactly as before and the anchor tick defers
   (`ranged_tick_is_live`, hunter_ui.lua:262-269; `tick_once`, :326-335). A hidden bar runs
   no `OnUpdate`, so the anchor tick takes over. No double update, no lost frame.
4. **The configured half of the visibility rule still applies** (`ranged_ui_allowed`,
   hunter_ui.lua:194-210; used at :1835): class switch-off, the hand/spec enable gate
   (`check_bar_enable_settings`) and — only while the bar frame is not visible — the hand's
   own show rule (`hand_show_condition_met`). Ignoring the activity gate must not surface
   an aspect icon / badge in a state the user's "in combat only" rule hides. No new visual
   state is introduced: every state the set can now paint was already painted whenever the
   bar was visible.
5. **Layer parity.** The host is put on the bar frame's strata/level *before* the widgets
   are created (hunter_ui.lua:308-312, `sync_tick_host_layering` :278-303), so a child
   created afterwards defaults to bar-level + 1 and inherits the bar's strata — the exact
   effective layering the widgets had as the bar's children (the cast bar keeps its
   explicit bar-level + 2). The sync is cached per tick and only calls Set on a real change
   (the profile-wide draw-level / strata options can move the bar after the build).
6. **H3 guard discipline** (`ui.poll`, hunter_ui.lua:338-367): the whole tick is pcall'd,
   failures counted, announced once (pcall'd chat path), and after 25 throws the hook is
   uninstalled and the set hidden — the power_bar/weave_range pattern. The per-subfeature
   `st.guard.run` sites inside `ui.update` are unchanged.

### Why the host is the anchor frame and not a new driver frame

A dedicated `SwedgeTimerHunterUIDriver` frame is the shape every sibling module uses
(hud/rotationtext/practice_ui/power_bar/weave_range/enemy_swing) and would be the cleaner
long-term ownership. It creates a 7th hunter frame at build time, and
`tests/bars_state.lua:1059` pins the hunter build-time frame census exactly
(`got 21, want 20` — reproduced). That pin is in a file outside this lane's write scope
(`tests/hunter_state.lua` only), and the established workshop rule for it is the one
`hunter_ui.lua`'s lazy badges already document: **do not move that census from this lane**
(the widget is created lazily "so the build-time widget census (bars_state,
reconcile-owned) is untouched until reconcile hoists it"). So the hook is hunter-owned and
hunter-installed, but hosted on the addon's existing per-hand frame.
**Follow-up (reconcile/owner):** hoist a dedicated driver frame and bump the HUNTER
`extra_frames` 6 -> 7 in `tests/bars_state.lua`; the tick body (`ui.poll/tick_once`) moves
unchanged. Until then this lane stays green.

## Proof

### Gate

- `bash tests/run.sh`: **54 steps, 0 failed**; `luacheck .`: **2 warnings / 0 errors in 97
  files** (the documented floor; the two new warnings this lane introduced were fixed).
- `lua5.1 tests/hunter_state.lua`: **PASS, 2040 checks** (was 1909).
- `lua5.1 tests/bars_state.lua`: **PASS, 1249 checks**. `lua5.1 tests/range_source_state.lua`:
  **PASS, 148 checks**. Both suites drive the set through the bar tick and still pass —
  the visible-bar path is unchanged.

### New pins (`tests/hunter_state.lua` §14n, line 3236)

- Host wiring: `ui.tick_host` is the ranged hand's anchor frame, parented to UIParent and
  shown; the anchor carries the hunter `OnUpdate`; the host starts on the bar's frame level
  and follows a later level change.
- Parentage/geometry: cast bar, range helper, Rapid Fire bar, aspect icon, BW/Frenzy badges
  parent to the host; the cast bar's points still read the **ranged bar frame**; the Rapid
  Fire bar still stacks above the cast bar; the range helper keeps its bottom edge on the
  ranged bar and its -3 gap; the RF bar keeps width 275 and the helper width 7; the cast bar
  keeps bar-level + 2 and the auto-leveled widgets bar-level + 1 (the mock now models the
  client's child-level rule).
- **Hidden-bar paint (the defect)**: with `ranged_bar_frame:Hide()` the host's real
  `OnUpdate` is invoked and — without touching the ranged hand — a Steady Shot cast shows
  the cast bar with its live label and no-clip tint, a Bestial Wrath badge shows, the range
  helper shows; the ranged bar is still hidden afterwards (**never resurrected**).
- **No double tick**: with the bar visible and its own `OnUpdate` installed, the host tick
  defers (the cast bar stays hidden until the bar tick runs); the bar tick then paints it.
  A visible bar *without* its `OnUpdate` leaves the frame to the host instead of blanking.
- **Inert**: ranged hand disabled after the build -> the host tick performs **zero** cast /
  aura / range reads and hides the set; `ST.ranged = nil` -> same, no throw; §14n-i (Retail
  shape: disabled ranged hand) -> set unbuilt, no host claimed, **no hook installed on the
  anchor**, zero casting reads.
- **Config gate**: class switch-off hides the set; a failing show rule hides it while the
  bar is idle; a met rule lets it paint; `check_bar_enable_settings` false hides it.
- **Guard**: 25 throwing anchor ticks are counted, the hook uninstalls, the set hides.
- Re-cut NILSWEEP HU2 (line ~6660): the same nil-class-row leg now also drives the anchor
  tick (the new source while the bar is hidden) and still stays contained and hidden.

### Red-first mutations (on a `/tmp` rsync copy: Media/docs/.git excluded)

(Environment note: this sandbox discards `/tmp` between tool calls, so each proof ran the
copy -> mutation -> suite sequence inside one shell invocation. The copy recipe is the
standing `/tmp/opencode` rule: `rsync -a --exclude=Media --exclude=docs --exclude=.git`.)

- **M1 — revert to the pre-fix ranged-tick-only wiring** (parent the widgets back to the
  bar frame, no anchor hook): **104 of 2040 checks fail**, including
  `FAIL HU-37: a Steady Shot cast paints while the ranged bar is hidden (got false, want true)`,
  `FAIL HU-37: the range helper paints while the ranged bar is hidden`,
  `FAIL HU-37: a proc badge paints while the ranged bar is hidden`,
  `FAIL HU-37: the anchor tick takes over the frame the bar's tick stops running`.
  `bars_state` stays green under M1 (the census/parentage pins do not see the wiring).
- **M2 — keep both sources** (drop the `ranged_tick_is_live` defer): **1 of 2040 checks
  fails**, `FAIL HU-37: the anchor tick defers while the visible bar's own tick is live
  (got true, want false)` — the no-double-tick pin.

## What still needs a live client

Offline proves the wiring, the parent chain, the layer parity and the tick behaviour; it
cannot prove client rendering. The audit's own note stands: **"a hidden frame runs no
OnUpdate / a hidden parent hides its children" is UNVERIFIED offline** (standard client
semantics, relied on by this repo's own code comments). In-client pass:

1. Hunter, bow equipped, **Auto Shot OFF**, no shot for a while: cast Steady Shot -> the
   cast bar paints above the (hidden) ranged-bar row and hides when the cast ends.
2. Auto Shot ON -> the ranged bar shows and the set behaves exactly as before; toggle it
   off and stop shooting -> the bar hides inside the activity window while a repeat cast
   still paints; no flicker/duplicate repaint.
3. Enable the BW / Frenzy / OOM / LnL / trap toggles: a proc while the bar is hidden shows
   the badge; the range helper paints with a target while the bar is hidden.
4. Out of combat with no target (default "either" rule): **no** floating aspect icon /
   badge while the bar is hidden (the show-rule leg); with a target it may paint (intended:
   the set is decoupled from the swing bar).
5. Options: change the profile draw level / frame strata and drag the ranged bar — the set
   keeps its position/width/layering; class switch-off hides the set; Retail (no
   `UnitRangedDamage`) creates nothing and installs no hook.
6. `/st diag`: no new hunter guard sites / no `bar_hook_errors` increase; the anchor frame's
   drag/lock behaviour is unchanged (the hunter uses only its `OnUpdate` slot).

## Residuals / notes (not fixed here)

- **First-tick build edge (pre-existing):** the set is still built from `post_init` or the
  first bar tick. If a hunter equips a ranged weapon mid-session while *every* bar stays
  hidden (out of combat, no target, Auto Shot off) the set is not built until a bar ticks.
  Unchanged from before; not made worse by this lane.
- **Anchor strata side effect:** when the user customises `frame_strata`, the host adopts
  it, so bars.lua's invisible hiding proxy (an anchor child) inherits the same strata. No
  rendering change (it has no regions); flagged for the in-client pass.
- **Existing widget frame levels** are assigned at creation (as before); a later
  `draw_level` change moves the bar frame but not the already-created widgets — pre-existing
  behaviour, unchanged by this lane (the host itself follows).
- `ranged_ui_allowed` calls main.lua's `check_bar_enable_settings` / `hand_show_condition_met`
  when present and is nil-safe when a sandbox does not model them; both exist in the real
  addon (`main.lua:285`, `:2897` at this snapshot; another lane is editing main.lua for the
  /st diag hide-reason fields, so these are function-name citations, not frozen lines).

## Evidence index

- `hunter_ui.lua:194` gate; `:233-367` the tick/host block; `:671` build claim; `:1835`
  update gate; `:1866` on_bar_update.
- `tests/hunter_state.lua:46-60` `tick_host`; `:3236` §14n; `:3405` §14n-ii; `:3426` §14n-i;
  `:6701` NILSWEEP HU2 re-cut; sandbox mock script/layer changes at `:1890-1960`.
- `main.lua:265-288` `ST:hide_bar`; `main.lua:2961` `ST:handle_bar_visibility`; `bars.lua:84-92`
  anchor creation; `bars.lua:611` anchor Show; `tests/bars_state.lua:1059` the frame census.
  (main.lua lines move under the concurrent `/st diag` lane - citations name the functions.)
