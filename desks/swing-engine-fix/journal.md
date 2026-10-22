# Desk: swing-engine-fix (engine lane, ses_e9b0ee35affefEeJkKOsCqJlH)

Write scope ONLY: main.lua dispatcher/handlers/init/equip/registration region
+ compat.lua family detection + api.get_time. Do NOT touch: bars.lua, hunter
files, swing_source.lua, tests/run.sh, vendored Libs, TOCs, versions, options.

## Worked on

- 2026-10-22: opened desk. Read first per dispatch: desks/journal.md lane
  table (parallel dispatch row: display/engine/harness disjoint by file),
  bench/swing_wire_status_2026-10-21.md (offline-proven only, stubbed
  engine), bench/proctor_swing_gap_2026-10-22.md (Pins 1-3 usable as pin
  list, cross-client claims UNVERIFIED), hands-up HU-25/HU-28/HU-29/HU-30.
  Read-only behavior reference: /home/sam/SuperSwingTimer-WoW (no lift).
- Cross-client API truth ONLY via `git -C /home/sam/wow-ui-source show
  <branch>:<path>` per branch (classic_era, classic_anniversary,
  classic_titan, live, origin/forever). Checked-out branch is classic_era.
- Verified by reading (no edits yet): dispatcher strip (main.lua:990-997)
  covers all six SWING_TIMER_* events + player/target leads + hand-only
  STOP; Forever numeric-first passes through. Registration/init/deadline/D8
  rewire (main.lua:379-450, 808-823) sound. TOC order: lib line 18, main
  line 58 on all classic flavors. Only main.lua registers on the swing
  engine (no same-self overwrite). compat family detection + api.get_time
  + UnitRangedDamage/IsAutoRepeatSpell/IsMounted probes all present.

## Current state

- Per-break verdicts (offline, pre-edit):
  - Break 2 (TBC ranged, gate-failed): CONFIRMED mechanism. Lib isBCC gate
    (LibClassicSwingTimerAPI.lua:43) needs project 5 AND expansion level;
    on miss every BCC table stays empty and SUCCEEDED(75) no-ops for
    ranged (lib:600-606), while melee (CLEU SWING_DAMAGE, lib:397-414)
    survives. main.lua has NO fallback: UNIT_SPELLCAST_SUCCEEDED only
    forwards to the class hook (main.lua:1558-1568). Fix: app-side
    SUCCEEDED(75)+START_AUTOREPEAT fallback driver in main.lua, suppressed
    whenever the engine's ranged side is live (recency gate) so it never
    double-drives. Retail inert stand-in stays silent; Forever
    speed-first payloads pass through untouched.
  - Break 1 (mh START): full in-scope chain verified sound and
    harness-proven (real lib + real v7 + real dispatcher green on Era and
    Anniversary(1) happy legs). No in-tree main.lua cause found offline;
    hunt2 ranked D10 (stale copy) first, D8 second (D8 fixed since).
    Premise says the current tree IS copied, so D10 is excluded by premise
    and the cause is unverified in-tree. Deliverable: strip-completeness
    legs (every handler, every re-fire shape incl. hand-only STOP) +
    mechanism probe for engine-stamp clock domain + the strongest in-scope
    hardening correct under both outcomes, with UNVERIFIED items named.
- Next step: baseline focused runs, then implement (see todos).

## 2026-10-22 — Fallback landed, strip verified [signal:done]

- **Worked on:** implemented the TBC fallback (`main.lua` dispatcher stamp +
  `maybe_drive_ranged_fallback`; no compat change needed); verified the
  strip on a /tmp copy (all six events x all hands x all shapes, green);
  killed the clock-domain theory (lib self-aligns, lib:24-37) and a CLEU
  misread (lib:383 verified char-by-char).
- **Current state:** break 2 FIXED in-tree (correct under both gate outcomes;
  never double-drives — dispatcher recency stamp; stand-in/source excluded).
  Break 1 has no in-scope cause: full chain verified sound + harness-green;
  report filed as `bench/swing_engine_fix_2026-10-22.md` with per-break
  verdicts, suite outputs, M1-M4 mutations, and UNVERIFIED items (diag
  close-outs) + a display-lane handoff (bars throw-path hypothesis) and
  harness-lane leg filing. Focused runs on the final tree: real_wire 482/0
  (3 xfail HU-29), main_init 975, bars_state 907, wiring 876/0, luacheck 2/0
  floor. /tmp fallback proof 999 green; M1/M2/M3/M4 each red on direct legs.
  All /tmp copies removed. CRLF intact, no line over 150.
- **Next step:** orchestrator reconciles; operator copies `main.lua` and
  reports `/st diag` (`swing_mainhand`, `callback_errors`, `proj=/exp=/bcc=`).

## 2026-10-22 — Operator-confirmed lib facts reconciled (CLEU path)

- **Worked on:** operator pasted the lib, ruled the CLEU path the break, and
  confirmed the pasted copy matches vendored v32 (same defects — the lib
  stays untouched per HU-29, our side routes around). Re-verified all four
  facts char-by-char against
  `Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua`:
  1. lib:397 first branch catches ALL SWING_MISSED (DAMAGE or MISSED), so the
     lib:415 PARRY arm is dead code. Routing: our side never depends on lib
     parry-haste UPDATEs — the fallback implements no parry logic and reads
     no parry state. MISSED routing/parry pins stay harness-owned (already
     xfail'd there). No code change.
  2. lib:257 `getUnit` second branch compares `self.player.id` (copy-paste;
     should be `self.target.id`), so `getUnit("target")` returns nil and the
     lib ignores all target-unit UNIT_* events. Player path unaffected
     (`"player"` matches the first branch). Routing: our side is player-only
     throughout (SUCCEEDED handler returns on non-player units; fallback
     reads player bars only); the dispatcher's "target"-lead strip is a dead
     shape anyway (the lib's re-fire only fires for player units). No code change.
  3. lib:456 CAST_START and lib:772 FAILED_QUIET ranged arms are both
     isClassic-only — TBC ranged lives on SUCCEEDED(75)+autorepeat alone.
     This SHARPENS the fallback requirement under both isBCC-gate outcomes
     (gate-pass: engine needs autorepeat for ranged; gate-fail: our driver
     is the only ranged driver). The implementation already matches exactly
     that shape; sharpened its header comment to cite lib:456/772
     (comment-only edit, main.lua; suites re-run green below). No logic change.
  4. lib:46 isMists compares the constant to itself (always true at
     project 19). Harmless in practice (Mists ships no lib) and irrelevant to
     our routing: compat family detection is independent of lib flags
     (own project-id/interface logic). Noted, low priority, no change.
- **Current state:** none of the four alters the break-1 verdict. Facts (1)
  and (2) are consistent with PARTIAL symptoms (no parry-haste anywhere;
  target-unit swings unhandled) but neither touches the player-unit
  SWING_DAMAGE path (`getUnit(sourceGUID)` via `player.GUID`, first branch
  intact) — so they cannot explain total mh-START death with ranged alive.
  The diag close-outs in the bench report stand. Final tree re-verified:
  main_init 975 PASS, luacheck floor held (main.lua's one warning is the
  pre-existing KEEP-ruled `table.pack` shim), CRLF intact.
- **Next step:** orchestrator reconciles; operator copies `main.lua` and
  reports `/st diag` per the bench report.

## 2026-10-22 — HU-31 scope ruling reconciled (Wrath in, Retail/Forever out)

- **Worked on:** binding ruling HU-31 — the lib-driven swing path must work
  for classic_era, classic_anniversary AND titanforge; Retail/Forever keep
  their own APIs. Verified the Wrath branch holds with zero code change:
  `_Wrath.toc` ships the lib (line 18, Interface 38002); the isWrath block
  keys Auto Shot 75 (`ranged_swing`, lib:1079+) with the same
  binary-expansion-level gate fragility as isBCC; the fallback is
  family-agnostic (engine-silence key) and Wrath's extra engine liveness
  (melee swings also START ranged, lib:405-413) only strengthens
  suppression; compat detects WRATH both ways. Retail/Forever stay intact
  and silent, triple-covered (`swing_engine` gate, `st.is_mainline` gate
  even under a foreign lib copy, no Auto Shot 75 event on Retail);
  dispatcher stamp lives only in the unit-id-led branch. Re-verified:
  real_wire 482/0 (incl. Titanforge legs), main_init 975.
- **Next step:** (superseded by the build-points entry below).

## 2026-10-22 — Display-lane contract wired (build points) [signal:done]

- **Worked on:** read `bench/swing_display_2026-10-22.md` + display journal
  first. Wired main.lua build points to the `bar_is_built`/`ensure_bar`
  contract: new `ST:bring_up_hand(hand)` (frames via ensure_bar + one-time
  tick install; legacy unconditional path when bars.lua is absent so
  bar-less sandboxes keep exact behavior) called from `init_timers` and
  `PLAYER_EQUIPMENT_CHANGED`; nil-guards on `show_bar`/`hide_bar`/
  `lock_frames`/`unlock_frames` (unbuilt == disabled, no-op, no error).
- **Current state:** init/equip build points live in main.lua. Re-cut the
  stale bars_state construction pins the points necessarily invalidate
  (warrior/rogue ranged ship disabled → correctly unbuilt; `built` field +
  gated-off block incl. equip-point proof), documented below as absorbed
  owning-lane work — leaving the tree red was worse than the minimal
  stretch, and the alternative (init building unconditionally) would void
  HU-22. No other pin touched.
- **Owed, not this lane:** option-on wiring (wherever `db.<hand>.enabled`
  flips true — likely generated per-hand widgets; option_tables.lua is out
  of scope) must call `ST:bring_up_hand(hand)` (method, callable from the
  options layer); committed lazy-bars suite + run.sh line (orchestrator /
  queued lane). `bring_up_hand` was promoted local→method for exactly this.
- **Proof:** bars_state 885 PASS (re-cut) + M5/M6/M7 mutants red on /tmp
  copies (removed); main_init 975, real_wire 482/0 (3 xfail), hunter_state
  1744, hunter_guide 1970, hunter_window 213, hud 817, guide_contract 1052;
  luacheck 2/0 floor; CRLF intact. Bench report extended below.
- **Next step:** orchestrator reconciles; queued lane owns option-on +
  committed suite; operator copies `main.lua` + `bars.lua` and reports
  `/st diag` per the bench report.

- **Worked on:** binding ruling HU-31 — the lib-driven swing path must work
  for classic_era, classic_anniversary AND titanforge; Retail/Forever keep
  their own APIs (inert stand-in / swing_source), no classic-lib fallback
  for those two. Verified the Wrath branch holds with zero code change:
  - `_Wrath.toc`: `## Interface: 38002`, ships the lib (line 18) like the
    other classic flavors.
  - Lib Wrath tables key Auto Shot 75 (`ranged_swing`, isWrath block
    lib:1079+), and the isWrath gate (lib:44) has the same
    binary-expansion-level structure as isBCC — same fragility, so the
    fallback carries Wrath ranged under a gate miss exactly as on TBC.
  - compat detects WRATH both ways (project id, compat.lua:57; interface
    major 3), `st.is_mainline` false there; `api.get_time` identical.
  - The fallback is family-agnostic by design (keys on engine silence, not
    family), and Wrath's extra engine liveness (melee swings also START
    ranged, lib:405-413) only strengthens the recency suppression. Wrath
    registers the autorepeat events (classic line, main.lua OnInitialize).
- **Worked on:** Retail/Forever exclusion walk (must stay intact + silent):
  triple-covered — (1) `swing_engine ~= "vendored-lib"` returns before any
  read/write (inert-standin on Retail, forever-source on Forever, including
  the D8 deadline/rewire assignments); (2) `st.is_mainline` returns even if
  a foreign lib copy contaminated `STL`; (3) Retail has no Auto Shot 75
  event to trigger on anyway. Dispatcher stamp lives only in the
  unit-id-led strip branch, so Forever's numeric-first payloads pass
  through untouched. No notices, no timers, no state writes on those two.
- **Current state:** no code change for HU-31 — the design already held for
  Wrath and already excluded Retail/Forever. Final tree re-verified after
  the reconciliation read: real_wire 482/0 (3 xfail HU-29, incl. Titanforge
  legs), main_init 975 (Wrath-default profile), luacheck 2/0 floor.
- **Next step:** orchestrator reconciles; operator copies `main.lua` and
  reports `/st diag` per the bench report.
