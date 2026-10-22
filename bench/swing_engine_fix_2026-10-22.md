# Swing engine-lane report (2026-10-22, desk `swing-engine-fix`)

Scope: main.lua dispatcher/handlers/init/equip/registration region +
compat.lua family detection + api.get_time. Untouched: bars.lua, hunter
files, swing_source.lua, tests/run.sh, vendored Libs, TOCs, versions,
options. No compat.lua change was needed (all probes already present).

## Per-break verdicts

### Break 2 (TBC ranged, gate-failed) — CONFIRMED mechanism, FIXED in main.lua

- The lib's isBCC gate (`Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:43`)
  needs project 5 AND the binary-provided expansion level. On a miss every
  BCC table stays `{}` and the lib's SUCCEEDED(75) arm
  (`LibClassicSwingTimerAPI.lua:600-606`) never fires ranged, while melee
  (CLEU SWING_DAMAGE, lib:397-414) survives. main.lua had NO fallback: its
  UNIT_SPELLCAST_SUCCEEDED only forwarded to the class hook.
- Fix (`main.lua`, only file changed):
  - `ST:UNIT_SPELLCAST_SUCCEEDED` now also calls
    `self:maybe_drive_ranged_fallback(spell_id)` (main.lua:~1570).
  - New `ST:maybe_drive_ranged_fallback` (main.lua:~1580-1665): drives the
    ranged cycle on spell 75 (Auto Shot — the same id the lib's Era/BCC
    `ranged_swing` tables key, lib:955/1066; event payloads are numeric on
    every family so no name-vs-id issue). Gates, in order: 75 only;
    `swing_engine == "vendored-lib"` (Retail inert stand-in and the Forever
    source engine are excluded outright — the stand-in stays silent, Forever
    speed-first payloads pass through untouched); not `st.is_mainline`;
    the class has a ranged hand; auto-repeat on (cached hunter flag, else the
    live pcall-guarded `api.IsAutoRepeatSpell` probe, mounted excluded);
    engine-ranged silence (the dispatcher's stamp must be older than two
    full cycles, or absent); a speed source (`api.UnitRangedDamage`, else the
    hunter-synced duration — never invents a cycle: no source means no drive).
  - The drive routes through the REAL dispatcher speed-first
    (`callback_event_handler("SWING_TIMER_START", speed, now+speed,
    "ranged")`), so it is pcall-isolated, counted by `note_swing_wire`,
    and can never read as engine payload (no unit-id lead, no liveness
    stamp). Cycle completion goes through the shared STOP path via a
    `fallback_timer` armed for `speed` seconds; the dispatcher's engine
    ranged START/UPDATE cancels it (engine timers rule again), as does the
    next fallback shot. First-shot convergence (nil stamp, engine alive) is
    one harmless converged cycle, documented in code.
  - No double-drive when the lib path is alive: the dispatcher stamps
    `ST.ranged_engine_stamp` on every engine (unit-id-led) ranged
    START/UPDATE (main.lua:~990-1010); a fresh stamp suppresses the fallback.

### Break 1 (mainhand START) — no in-scope cause found; strip VERIFIED complete

- Strip (`main.lua:990-997`, pre-existing) verified complete, not assumed:
  /tmp-copy probe drove `callback_event_handler` with all six SWING_TIMER_*
  events x {player lead, target lead, Forever numeric-first / hand-only STOP}
  x {mainhand, offhand, ranged} plus unknown-hand once-notice and GCD
  passthrough — all green, zero FAILs (copy removed after).
- Registration/init/deadline/D8-rewire re-read sound; only main.lua registers
  on the swing engine (no same-self overwrite — grep over the tree); TOC
  order holds (lib line 18, main line 58 on all classic flavors).
- Two candidate mechanisms KILLED with file:line evidence:
  - Clock-domain split: the lib stamps in `CanonicalGetTime()`, which learns
    the precise-to-GetTime offset ONCE and thereafter ticks in the GetTime
    domain (lib:24-37) — the same domain main.lua/bars.lua compare in. There
    is no split to align; the sandbox's unified clocks model the client
    faithfully here. (swing_source's raw-precise warning, swing_source.lua:70-73,
    does not apply to the lib.)
  - CLEU parsing: the handler's `sourceGUID`/`destGUID` positions map
    correctly once the leading `event` arg is counted (lib:383) — rechecked
    character by character after an initial miscount.
- Real-lib harness (real_wire_state 482/0) + main_init (975) both green on
  the final tree. The remaining mh-specific hypotheses live OUTSIDE this
  scope (bars.lua throw paths in `on_bar_active`/`set_bar_color` — the
  dispatcher isolates handler throws with a once-per-event notice, so a
  throwing mh path would print exactly once and freeze the bar at seed;
  owned by the display lane) or need in-client evidence (see UNVERIFIED).

## Validation (focused — full run.sh is the orchestrator's)

- `lua5.1 tests/real_wire_state.lua` → 482 checks, 0 failures (3 xfail, HU-29).
- `lua5.1 tests/main_init_state.lua` → PASS 975 checks.
- `lua5.1 tests/bars_state.lua` → PASS 907 checks.
- `lua5.1 tests/wiring_check.lua` → 876 checks, 0 failures.
- `luacheck main.lua compat.lua` → 2 warnings / 0 errors (the floor: both
  KEEP-ruled, pre-existing).
- /tmp-copy proof of the fallback (legs appended to the COPY's
  main_init_state only, copy removed after): 999 checks PASS — drive on
  silent engine, suppression on live engine, stale-stamp re-drive, engine
  UPDATE cancels the pending stop, synced-duration path, no-speed no-drive,
  full STOP lifecycle, non-75 and no-autorepeat silent.
- Mutations (fresh /tmp copy each, removed after) — every guard proved
  load-bearing (red on its direct leg):
  - M1 spell-id guard neutered → "non-Auto-Shot arms no stop timer" FAIL.
  - M2 silence window neutered → "live engine suppresses" + "arms no timer" FAIL.
  - M3 autorepeat gate neutered → "without autorepeat no stop timer" FAIL.
  - M4 dispatcher stamp/cancel neutered → "engine UPDATE cancels" + "cleared" FAIL.
- CRLF intact (2377/2377 lines); no touched line over 150 chars.

## Reconciliation (2026-10-22): operator-confirmed lib-side CLEU facts

The operator pasted the lib and ruled the CLEU path the break; the pasted
copy matches vendored v32 defect-for-defect (re-verified in-tree). The lib
stays untouched (HU-29); our side routes around each fact (no logic change
beyond a comment citation — see below):

1. **Parry arm dead (lib:397 vs lib:415).** The first branch catches ALL
   `SWING_MISSED`, so the `amount == "PARRY"` arm never runs. Our side never
   depends on lib parry-haste UPDATEs: the fallback implements no parry logic
   and reads no parry state. MISSED-routing/parry pins stay harness-owned
   (already EXPECTED-FAIL there pending HU-29).
2. **Target-unit resolution broken (lib:257).** The `getUnit` copy-paste
   (`self.player.id` where `self.target.id` belongs) makes
   `getUnit("target")` return nil, so the lib ignores all target-unit UNIT_*
   events. The player path is intact (`"player"` matches the first branch).
   Our side is player-only throughout (SUCCEEDED handler gates non-player
   units; fallback reads player bars), and the dispatcher's "target"-lead
   strip is a dead shape (the lib re-fires player units only).
3. **TBC ranged driver narrowed (lib:456 + lib:772).** Both ranged arms are
   isClassic-only, so TBC ranged lives on SUCCEEDED(75)+autorepeat alone —
   under BOTH isBCC-gate outcomes (pass: engine still needs autorepeat;
   fail: our driver is the only driver). The fallback already implements
   exactly this shape; its header comment now cites lib:456/772
   (comment-only edit in main.lua, suites re-run green). This sharpens, not
   widens, the fallback requirement.
4. **isMists self-compare (lib:46).** Always true at project 19; harmless
   (Mists ships no lib) and irrelevant to our routing — compat detects the
   family from project id / interface version independently of lib flags.
   Noted, low priority.

Neither (1) nor (2) touches the player-unit SWING_DAMAGE path, so they are
consistent with partial symptoms (no parry-haste; no target-unit handling)
but cannot explain total mh-START death with ranged alive — the break-1
UNVERIFIED items and diag close-outs above stand unchanged.

## Reconciliation (2026-10-22, HU-31): Wrath in, Retail/Forever out

Binding scope ruling: the lib-driven swing path must work for classic_era,
classic_anniversary AND titanforge (WotLK-line, `_Wrath.toc`, interface
38002). Retail/Forever keep their own APIs — no classic-lib fallback there.

- **Wrath holds with no code change.** `_Wrath.toc` ships the lib (line 18);
  the isWrath block keys Auto Shot 75 in `ranged_swing` (lib:1079+), and its
  gate (lib:44) shares the isBCC structure (binary expansion-level half), so
  the fallback carries Wrath ranged under a gate miss exactly as on TBC. The
  fallback is family-agnostic (engine-silence key, not family key), and
  Wrath's extra engine liveness (melee swings also START ranged, lib:405-413)
  only strengthens suppression. compat detects WRATH via project id and
  interface major 3; `api.get_time` is family-identical.
- **Retail/Forever stay intact and silent, triple-covered:** (1)
  `swing_engine ~= "vendored-lib"` returns before any read/write (covers the
  inert stand-in, the source engine, and the D8 deadline/rewire assignments);
  (2) `st.is_mainline` returns even under a foreign lib copy; (3) Retail has
  no Auto Shot 75 event regardless. The dispatcher stamp runs only in the
  unit-id-led branch, so Forever's numeric-first payloads are untouched.
- Re-verified after reconciliation: real_wire 482/0 (incl. Titanforge legs),
  main_init 975 (Wrath-default profile), luacheck 2/0 floor.

## Build points (2026-10-22): display-lane contract wired in main.lua

Read `bench/swing_display_2026-10-22.md` + display journal first, per
dispatch. main.lua changes only (bars.lua/hunter files untouched):

- New `ST:bring_up_hand(hand)` (main.lua, above `init_timers`): frames via
  `ST:ensure_bar` (idempotent, gated) + one-time tick install (skips when a
  script is already present). When bars.lua is absent (offline suites that
  stub the visuals) it keeps the legacy unconditional build, so those suites
  keep byte-exact behavior. Promoted local→method so the options layer can
  reuse the seam for option-on. Called from `init_timers` (replaces the
  direct `init_visuals_template`/`set_bar_texts`/tick-install tail; state
  seeds stay unconditional) and `PLAYER_EQUIPMENT_CHANGED` (after
  `check_weapons`, before `on_attack_speed_change`).
- Nil-guards (unbuilt == disabled, no-op): `hide_bar` early-returns on a nil
  bar frame; `show_bar` early-returns on a nil bar frame; `lock_frames`/
  `unlock_frames` skip hands with no anchor frame.
- Necessitated re-cut (stale pins asserted the superseded unconditional
  build; HU-22 voids them): warrior + rogue specs gained `built =
  {"mainhand","offhand"}` (their ranged bars ship disabled — verified in
  `config_presets` warrior/rogue hand defaults `ranged.enabled = false`
  with weapons equipped, so the gate outcome is `enabled=false` → unbuilt);
  the construction loop asserts `spec.built or spec.hands`; new §1b block
  pins the gated-off hands (no anchor, `ensure_bar` false, show/hide
  no-op pcall-clean, no tick) plus the equip build point end-to-end
  (enable + `PLAYER_EQUIPMENT_CHANGED(18)` → built + tick installed).
  Filed as absorbed owning-lane work: leaving the tree red was worse, and
  init-building unconditionally would void HU-22. No other pin touched.
- Owed, not this lane: option-on wiring (wherever `db.<hand>.enabled` flips
  true — option_tables.lua is out of scope) must call
  `ST:bring_up_hand(hand)`; committed lazy-bars suite + run.sh line
  (orchestrator / queued lane).

## Validation — build points (focused)

- `bars_state` 885 PASS (re-cut); `main_init` 975; `real_wire` 482/0
  (3 xfail HU-29); `hunter_state` 1744; `hunter_guide_state` 1970;
  `hunter_window_state` 213; `hud_state` 817; `guide_contract` 1052.
- `luacheck main.lua compat.lua` → 2 warnings / 0 errors (floor held).
- /tmp-copy mutations (fresh copies, removed after): M5 (db.enabled gate
  neutered → gated hands build, counts revert 10→14 etc.) red; M6
  (hide_bar guard removed → unbuilt hide hard-errors) red; M7 (build points
  removed → nothing builds, handle_oor hard-errors on the missing frame)
  red. M7 additionally confirms `handle_oor_hand` relies on the build
  points (bar_is_enabled ⟺ built, so no guard needed there while the
  points stand).
- CRLF intact (2429/2429 lines).

## UNVERIFIED items (closing evidence for each)

- U1 (break-1 cause): needs one in-client `/st diag` after the copy:
  `swing_mainhand=` counts (zero = delivery/registration path — orchestrator
  re-check; climbing = handlers run and the bar side drops it — display lane),
  `callback_errors=` (nonzero + the once-only "failed and was isolated" line
  names the throwing handler), the one-time "Swing timer bars are unavailable"
  notice (never printed = deadline path not taken), `proj=/exp=/bcc=` (the
  gate outcome). A wrong-folder copy (Era vs Anniversary) still explains a
  total-freeze report with zero tree defect (hunt2 D10) — the diag's proj/exp
  line distinguishes it.
- U2 (TBC gate outcome): same diag `proj=/exp=/bcc=` line — decides whether
  the shipped lib path or the new fallback carries Anniversary ranged.
- U3 (fallback live behavior): hunter auto-shot cycle advances the ranged bar
  with `swing_ranged` STARTs climbing and no double-length cycles; melee START
  still engine-driven (unchanged path).
- Filed for the harness lane (owns `tests/real_wire_state.lua`): the fallback
  needs Pin-1-style legs through main.lua-side event delivery (the current
  harness drives lib events only, so the D2-nil xfail correctly stands — it
  pins the LIB, not the app fallback). Suggested legs: SUCCEEDED(75) with a
  stubbed-silent engine drives; with a speaking engine suppresses; stop-timer
  lifecycle; Retail/Forever inert. Do NOT move the D2 xfail — HU-29 still rules
  the vendored file.
