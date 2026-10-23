# Release audit — core engine (2026-10-22, desk `audit-core`)

Scope: main.lua, bars.lua, compat.lua, swing_source.lua, diag.lua, utils.lua
(+ core tests). LibLatencyMonitor vendored — untouched, no finding filed
(nothing in it is read by the audited paths except the LATENCY_CHANGED
registration, which is guarded and diag-surfaced). Libs/TOCs/run.sh/versions,
classes/*, hud, options, practice files untouched.

## Skills confirmation

@bench-read ran (desks/journal.md lane table through the release-audit
dispatch + bench/swing_engine_fix_2026-10-22.md +
bench/swing_cleu_parity_2026-10-22.md + bench/clock_align_2026-10-22.md +
hands-up.md HU-22/23/25/28/29/31; journals before artifacts, new material
only). @desk-open ran (desks/audit-core/ created with journal.md + .signals/,
worked there only). @desk-journal running (trail in desks/audit-core/journal.md).
@signal-write runs at close (done signal + journal marker).

## Verdict: NO BLOCKER. 6 hardenings landed (all unreachable-state,
behavior-identical in-game), 1 phantom retracted, reachable paths verified clean.

## Fixed (main.lua + bars.lua only)

### F-GETTERS — main.lua getters indexed through nil (would-be crash, hardening)
main.lua:192-211 `get_anchor_frame/hiding/bar/visuals` did
`self[hand].anchor_frame` with no guard: an unknown hand throws `attempt to
index nil`. Production-unreachable (bars.lua loads after main.lua on all 7
flavor TOCs and overrides all four with nil-safe versions — verified
7/7 TOCs carry bars.lua, SwedgeTimer.toc:58-59 order main→bars), but live in
every offline sandbox that loads main.lua without bars.lua (main_init_state).
Now nil-safe, mirroring bars.lua semantics. Pinned by main_init §4b-iii
(4 checks); M1 neuters → suite aborts at main_init_state.lua:895 with the
exact nil-index (exit 1, red). bars_lazy §6(a) pins the same contract at the
bars layer (still 52/0 with main.lua neutered — proves the override layering).

### F-BARISBUILT — built-predicate covered only the anchor (contract, hardening)
bars.lua `bar_is_built` read `get_anchor_frame(hand) ~= nil` while ~12
consumers touch the visuals chain or deeper (configure_draw_layers,
set_gcd_width via frame, gcd markers, deadzone, texts, color, onupdate).
A partial chain (anchor without children) would crash them. Partial chains
are unreachable (init_visuals_template builds synchronously), so this is a
centralization, not a behavior change: predicate now reads
`get_visuals_frame(hand) ~= nil` — the thing every consumer touches. One
guard instead of twelve re-checks; ensure_bar self-heals a partial by
rebuilding. Pinned by bars_lazy §6(b)(c) (5 checks); M2 reverts to
anchor-only → 4 FAILs (red).

### F-GCDVF — GCD_OVER double nil-hop (hardening)
main.lua GCD_OVER did `self:get_visuals_frame(hand).gcd_bar:Hide()` behind
the bar_is_built gate. Now
`local vf ...; if vf ~= nil and vf.gcd_bar ~= nil then vf.gcd_bar:Hide()`.
Reachable states unchanged (built ⟹ both exist). Pinned by §6(d)
(bar_is_built seam absent + unbuilt hand); M3 reverts → FAIL (red).

### F-HIDING — hide/show hiding-anchor second hop (hardening)
hide_bar + show_bar (3 sites) indexed `get_hiding_anchor_frame(hand):Show/Hide`
unguarded after the bar_frame check. Now local + nil-guarded. Co-created with
bar_frame in init_visuals_template, so reachable behavior identical; existing
bars_state:1319 pins the hide path. The nil-hiding branch itself is
unreachable and unpinnable — disclosed, not oversold.

### F-OOR — handle_oor_hand db + frame (hardening)
main.lua:handle_oor_hand read `db.dim_oor` and `frame:SetAlpha` unguarded.
Now `type(db) ~= "table"` and `frame == nil` early-returns. Reachable states
unchanged (callers pre-check bar_is_enabled ⟺ built while build points
stand). Pinned by §6(e) (frameless hand + unknown hand); M3 reverts → 2 FAILs.

### F-TICK — onupdate_common frame/db/d (hardening)
bars.lua tick fetched frame/d/db with no nil check after the build gate.
Now all three guarded (frame nil / d non-table / db non-table → silent
return, never a per-frame throw out of an unprotected OnUpdate). Pinned by
§6(f) (frameless+live-state, nil hand table via stub); M4 reverts → 2 FAILs.

### F1-RETRACTED — alleged "inert-standin" deadline misspelling: NO BUG
First grep pass appeared to show main.lua:490 `ST.swing_engine =
"inert-standin"` vs :43 `"inert-standin"`, which would have broken the
option_tables.lua:524 practice gate after the deadline. Byte-level check
(od -c both lines; grep -c counts) proved BOTH lines already read
"inert-standin" (single hyphen, 2 occurrences tree-wide, 0 of the
double-hyphen form). The edit tool agreed (old==new rejection). NO CHANGE
MADE. Lesson: read hyphen-dense identifiers at byte level before "fixing".

## Verified clean (read, no change)

- Clock purity: zero raw GetTime()/GetTimePreciseSec() in shipped core code
  outside compat's aligned wrapper (offset learned once, GetTime domain) and
  the swing_source no-api fallback (allowlisted, production has st.api).
  bare floor/max/format are client globals (classic_era SharedXMLBase
  Compat.lua:30+); utils.simple_round safe in-client.
- Dispatcher/handlers: strip drops a leading player/target token on
  SWING_TIMER_* only; Forever numeric-first passes through; engine ranged
  stamp + fallback-cancel only in the stripped branch; pcall isolation with
  once-per-event notice + counts. CLEU indices (select 2/4/8/12/15 =
  subEvent/sourceGUID/destGUID/missType/amount) match the CombatLog tuple.
  COMBAT_LOG_EVENT_UNFILTERED registered classic-line only; spellcast
  lifecycle thin forwarders keep the init guard (H6 pattern).
- Build points / lazy gates: init_timers → bring_up_hand per iter hand;
  PLAYER_EQUIPMENT_CHANGED (16/17/18) → check_weapons + bring_up_hand +
  on_attack_speed_change; option_tables.lua:1053 enabled_setter → bring_up_hand
  on enable (read-only audit; options files out of scope, no change needed).
  handle_oor ⟺ built equivalence holds while the three build points stand.
- diag truth: engine strings uniform ("inert-standin" load + deadline +
  diag docs + option_tables + practice_ui all agree); config/flags/modules/
  ticks/secrets/ids/errors lines all read-only, pcall-wrapped, capped.
  print_runtime_diag proj/exp/bcc + swing_wire counts truthful (suppressed
  extras count as wire arrivals — correct, they ARE arrivals).
- Retail inert: stub nil-shape → engine_dead per hand; no CLEU registration;
  fallback + utility-reset gated to vendored-lib + not-mainline. Forever:
  PLAYER_SWING speed-first START / combat-exit STOP / attack-speed rescale /
  WEAPON_SLOT_CHANGED probe-gated — mapping intact, no classic-lib behavior
  built for Retail/Forever (HU-31 held).
- secret_guard surfaces: all new comparisons are on GUID strings / booleans /
  numbers from nil-safe wrappers; no secret-typed value reaches arithmetic or
  comparison. secret_guard_state 432 PASS unmodified.
- Residual (left as-is, disclosed): SWING_TIMER_START's
  `bar.is_full_timer:Cancel()` is unguarded while restart_swing_for_reset
  pcall-guards the same call. Unreachable-throw (always a real timer
  in-client, Cancel-carrying stubs in suites). Not worth the churn.

## Files changed

- main.lua: getters nil-safe; hide_bar + show_bar hiding guards;
  GCD_OVER vf/gcd_bar guard; handle_oor_hand db/frame guards.
- bars.lua: bar_is_built full-chain; onupdate_common frame/d/db guards.
- tests/bars_lazy_state.lua: §6 (15 checks).
- tests/main_init_state.lua: §4b-iii (4 checks).
Line endings preserved (main.lua CRLF 2754/2754, rest LF). No line over
150 chars added. No other files touched (parallel lanes own the rest of the
tree; full run.sh stays orchestrator-owned).

## Validation (focused)

- main_init_state 990 PASS (+6: 4 new legs + boot internals).
- bars_state 935 PASS. bars_lazy_state 52 PASS (37 + 15 new).
- wiring_check 872 checks / 0 failures / 3 accepted / 0 stale (no new
  "function" token in any main.lua handler span — the function_span counter
  is respected; clock allowlist untouched).
- real_wire_state 882 / 0 (3 xfail HU-29). swing_source_state 149 PASS.
  diag_state 260 PASS. secret_guard_state 432 PASS. enemy_swing_state 250/0.
  smoke 232 PASS.
- luacheck: tree 2 warnings / 0 errors in 90 files (the floor:
  main.lua:87 table.pack KEEP + 1 pre-existing); new test code clean
  (one self-introduced unused-var warning found and fixed).
- Mutations (fresh full-tree /tmp/opencode copies, removed after — all red):
  M1 getters neutered → main_init aborts at :895 exact nil-index (exit 1);
  bars_lazy stays 52/0 (bars override layering proven). M2 bar_is_built
  anchor-only → 4 FAILs. M3 GCD/handle_oor guards reverted → 3 FAILs.
  M4 onupdate guards reverted → 2 FAILs.

## UNVERIFIED (in-client only; validation owner: orchestrator)

- U1: per-hand sweep/STOP/reset + option-on build after the operator copy.
- U2: /st diag engine + swing_wire counts after copy.
- U3: the new guards are unreachable-state armor — in-client success is the
  ABSENCE of new errors, not a positive signal; nothing further is provable
  offline.
