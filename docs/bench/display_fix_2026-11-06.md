# Display fix — WoW Forever (2026-11-06)

Desk: `display-fix` (`desks/display-fix/journal.md`). Scope: the operator's two Forever
display reports — (A) a Hunter Auto Shot that fires but is sometimes not displayed, and
(B) the horizontal standalone range bar that worked then stopped displaying — plus the
operator ruling that the Auto Shot red zone is display-only.

Client target: WoW Forever / Camelot 1.60.1, Interface 16001, Mainline-code
(`st.family == "FOREVER"`, `swing_engine == "forever-source"`). Evidence base:
`bench/forever_display_audit_2026-11-06.md` (A-1/A-2/A-3/A-4, B-1/B-5/B-6/B-7, §8
red-zone verdict) and `desks/perf-audit/journal.md` (the on-disk
`bench/bars_perf_audit_2026-11-06.md` is a 17-line summary without the cited §4/§5; the
full census lives in that desk's journal). Every claim below is offline-proven; nothing
here is in-client proof.

## Baseline and end state

- Baseline at dispatch: tree 2.1.8 (all 7 TOCs + `main.lua:5`); `bash tests/run.sh`
  57 steps / 0 failed; luacheck 2 warnings / 0 errors in 100 files.
- ⚠ VERSION: a rogue read-only desk wrote **2.2.0** into the 7 TOCs and `main.lua:5`
  at 14:11. The operator-approved target is **2.1.8**; the Lead / release-version desk
  restores those fields. This desk did not touch any version field.
- End state (this desk's own suites): `swing_source_state` 188 checks, `main_init_state`
  1117, `hunter_state` 2080, `weave_bar_state` 140, `weave_range_state` 90,
  `engine_matrix_state` 110, `wiring_check` 905/0 with 0 stale accepts, `bars_state`
  1305, `diag_state` 389, `toc_check` 1104 — all green.
- **Full gate on the settled three-desk tree (final): `bash tests/run.sh` = 57 steps,
  0 failed; `luacheck .` = 2 warnings / 0 errors in 100 files** (the 2 warnings are the
  pre-existing `hunter_ui.lua` CAST_ZONE_SAFE/UNSAFE floor pair).

## Files changed (this desk only)

| File | Change |
|---|---|
| `swing_source.lua` | A-1: restricted/malformed `PLAYER_SWING` payload handling + equipped-speed cycle recovery + first-reject notice + diag counters |
| `main.lua` | A-2/R1 heartbeat; A-3/A-4 `check_weapons` + world-entry re-probe; A-4 weapon proof from the engine receipt; A-2 immediate visibility on ranged START/UPDATE/shot/autorrepeat; ranged activity window pin; B-1 guarded `weave_range` init + world-entry retry; `rf_heartbeat_errors=` + `weave=` diag tokens |
| `classes/hunter.lua` | A-4 numeric Auto Shot auto-repeat probe + shared `refresh_auto_repeat` (cooldown path, event path, throttled tick backstop) |
| `hunter_ui.lua` | red-zone display-only contract comment (code unchanged — audit §8 PASS) |
| `weave_range.lua` | B-5 explicit unknown face; B-6 recoverable quarantine; B-7 `diagnostic_text` |
| `tests/swing_source_state.lua` | A-1 pins (recovery, no-speed reject, first-reject notice, diag counters) |
| `tests/main_init_state.lua` | §10 re-cut + new heartbeat/guard pins; §21 weapon probe/window/immediate visibility/weave init+diag pins |
| `tests/hunter_state.lua` | red-zone display-only pins; A-4 numeric-id/throttle/tick-backstop pins; comment-blind `C_Spell` scope pin |
| `tests/weave_bar_state.lua` | B-5 unknown-face pins; B-6 consecutive/recoverable quarantine pins; B-7 diag pins |
| `tests/engine_matrix_state.lua` | A-1 crossfire re-cut: forever payload now pins fallback-when-readable + reject-when-not |
| `tests/wiring_check.lua` | deleted the 2 stale ACCEPTED rows the new guards invalidated |
| `tests/secret_guard_state.lua` | §8 (R5) re-cut in the follow-up pass: pins the new `check_weapons` contract (keep-on-unknown, readable-0 clears) via a local mirror + source-shape pins; wrapper pins unchanged |

Not touched: `bars.lua`/`utils.lua` (bars-perf desk), `power_bar.lua`/`compat.lua`/
`diag.lua` (powerbar desk), TOCs/README/CHANGELOG, `tests/bars_state.lua`,
`tests/power_bar_state.lua`, `tests/run.sh` (Lead), `Libs/`, `docs/swedge/`, git.
All edited files keep LF endings.

## Symptom A — Auto Shot fires but is sometimes not displayed

### A-1 HIGH — one rejected `PLAYER_SWING` was silent, and a restricted payload threw

Root cause (verified in-tree): `swing_source.lua:279` `on_player_swing` dropped a cycle when
the duration was not a positive number (`type(...) ~= "number" or swing_duration <= 0`)
and counted it only in session counters (`stats` at `:101`); the chat notice (`:132`) waited for
`SUSTAINED_REJECT_SECONDS = 5` **in combat**. A single bad payload was therefore exactly
"one shot consumed, the next recovers", with no user-visible signal. Worse, the
comparison itself was unsafe: a restricted (secret) payload passes `type()` and raises on
the first comparison, so one secret duration could throw out of `OnEvent` **before** any
counter was written.

Fix (`swing_source.lua`):
- `is_restricted(value)` / `usable_duration(value)`: probe `issecretvalue` before any
  branch/comparison; secret values can never reach arithmetic.
- `on_player_swing`: a restricted swing type is attributed as an unknown type and
  dropped; a restricted/malformed duration on a **known** hand is recovered from the
  equipped speed (`read_equipped_speed`: `UnitAttackSpeed`'s per-hand return, and for
  the ranged hand `UnitRangedDamage`'s first return, every read pcall'd +
  secret-checked) instead of dropping the cycle. Only "no readable fallback speed" is a
  counted reject — the cycle is never invented.
- `note_payload_reject` prints a once-per-session chat line on the FIRST reject (the
  5 s sustained notice keeps its own latch).
- `diagnostic_text` gains `speed_fallbacks=` and `first_reject_notice=`.

### A-2 HIGH (R1) — the visibility driver could stop for the session

Root cause (verified in-tree): `main.lua:2897` `rf_update` returned early on `rf_disabled`
before `set_bar_visibilities`/`handle_oor`, and those two calls sat **outside** the
pcall whose `C_Timer.After` re-arm was the last statement. Consequences: (a) one throw in
the visibility/alpha pass escaped the timer callback and the heartbeat was never
re-armed — every bar froze with no `rf_disabled` and no notice; (b) after three range
probe failures the session disabled range checking and every later tick returned at the
top, so a bar hidden at that moment never reappeared. A shot that landed while the bar
was hidden could not show it: showing lived only in that poll.

Fix (`main.lua`):
- `ST:run_bar_visibility_pass()` runs `set_bar_visibilities` and `handle_oor` in **their
  own pcalls**, counts failures in `rf_heartbeat_errors` (rendered by `/st diag`), and
  never lets a frame-side throw escape.
- `rf_update` is one guarded body with an **unconditional** final
  `C_Timer.After(delay, self.rf_tick_fn)`; a transient range-probe failure keeps the
  bounded backoff (and the previous paint) but the heartbeat still re-arms; the terminal
  failure and every later disabled poll still run the visibility pass and re-arm.
- Immediate visibility: a Forever ranged `SWING_TIMER_START`/`UPDATE` receipt, a
  completed-shot receipt (`UNIT_SPELLCAST_SUCCEEDED`), and a hunter
  `START/STOP_AUTOREPEAT_SPELL` each call `handle_bar_visibility("ranged")` in the same
  event, so a shot never waits for the 0.05 s poll. The vendored engine's UPDATE is
  deliberately NOT promoted to a receipt (it also re-times reset cycles).

### A-3/A-4 HIGH — `has_weapon` could silently turn false; the auto-repeat backstop was dead

Root cause (verified in-tree): `main.lua:986` `check_weapons` derived `ranged.has_weapon` from
`api.UnitRangedDamage` and `offhand.has_weapon` from `api.UnitAttackSpeed` with
`x or 0`; compat nils a restricted read, so "unknown" became "no weapon" →
`bar_is_enabled` false, the lazy build refused, the OOR alpha gated, and the probe only
ran again on equipment slots 16/17/18. Separately, `classes/hunter.lua:1007` (`refresh_auto_repeat`) / `:1080` (`on_autorrepeat_event`) probed
`api.IsAutoRepeatSpell(spell_token(75))`, which is the localized **name** on Forever,
while compat's id fallback only fires for numeric tokens — so the ranged activity gate's
designed backstop could be dead. The activity window could also be 1.5 s against a
longer cycle before the first engine speed stamp.

Fix:
- `check_weapons` only updates a hand on a **readable** number; nil/unknown keeps the
  previous value (a genuine unequip still answers 0). `PLAYER_ENTERING_WORLD` re-probes
  (the reliable read point).
- A Forever ranged/offhand `SWING_TIMER_START` proves that hand has a weapon: if the
  flag is not true it is set, `ensure_bar(hand)` runs (lazy-build point) and visibility
  is re-evaluated in the same event.
- `ST.HUNTER.refresh_auto_repeat(self, force)` is the one probe path (numeric `75` —
  the client's own form): forced from `SPELL_UPDATE_COOLDOWN` **before** its early
  returns and from `START/STOP_AUTOREPEAT_SPELL`, throttled to 4/s from the class tick
  as the missed-event backstop; a change opens/closes the bar in that event.
- `hand_activity_window("ranged")`: falls back to the hunter sync's
  `ranged.synced_duration` when the engine has not stamped a speed, and keeps the
  documented 2-cycle window (1.5 s floor / 8 s ceiling).

### Red zone — display-only contract (operator ruling)

Audit §8 verified the tree PASS: the zone updater writes only
`ui.cast_zone`/`cast_zone_marker`/`zone_*` latches, the cast-bar window cache is read
only by `gather_guide_inputs`, and no hunter module calls `show_bar`/`hide_bar`. This
desk added the explicit contract comment in `hunter_ui.lua:1055` (`update_cast_zone`) and
behavioral pins in `tests/hunter_state.lua` §W: enabled+live cycle → zone draws with the
bar/state untouched; disabled → zone hides, bar/state/cast bar untouched; absent zone →
no throw, no hide; throwing zone updater → isolated, bar and cast bar keep running.

## Symptom B — the horizontal range bar worked then stopped

### B-5 MED — unknown distance hid the bar

Root cause: `weave_range.lua:414` `update` hid whenever `st.api.UnitDistance("target")` was not a
number. On Forever the doc'd `UnitDistanceSquared` second return `checkedDistance` can be
false (Blizzard's own consumer only trusts it when true), compat normalises that to nil,
and the bar disappeared by documented contract. The operator explicitly wants the range
aid to stay visible.

Fix: target present + attackable + distance unknown now renders an explicit neutral face
— dim `UNKNOWN_COLOR` fill across the track and `"--"` — never a 0-looking empty bar and
never a disappearance. `wr.last_reason = "unknown-distance"` feeds the diag receipt. The
known-reading path, band maths, latching and the pure helpers are unchanged; the new
constants are additive.

### B-6 HIGH — driver quarantine was permanent

Root cause: `weave_range.lua:539` `wr.poll` removed its own `OnUpdate` (`SetScript("OnUpdate", nil)`) after 25
consecutive throws and hid the bar — session-long, with only one chat line and no diag
receipt.

Fix: the failure counter resets on success (already true) and quarantine now means:
driver stays **armed**, the last paint stays on screen, the body is skipped for a
backoff window (10 s, doubling to 60 s for repeated bursts), and the next window retries;
a recovered update clears the quarantine and paints again.

### B-1 HIGH — `weave_range.init` was an unguarded `post_init` tail

Root cause: the init call sat unguarded in `post_init`'s tail after
`interfaces_are_initialised`; one throw before/inside it left the driver uncreated for
the session with no retry.

Fix: `main.lua:1022` `ST:init_weave_range()` is a guarded seam - called from `post_init` at
`:1083` (pcall + one notice, idempotent, inert module respected) and retried exactly once
from `PLAYER_ENTERING_WORLD` (`:1774`) when the frame is still absent.

### B-7 LOW — no `/st diag` receipt

Fix: `weave_range.lua:590` `wr.diagnostic_text()` renders one `/st diag` token:
`weave=<on|off>:<yes|no>:<why>:<distance>:<state>:fail=<n>:q=<yes|no>` with `why` =
shown / no-target / not-attackable / unknown-distance / bad-reading / class-off /
profile-off / settings-off / no-class. `main.lua:3378` (inside `print_runtime_diag`) appends it via a
pcall (a throwing diag can never take the runtime line down). The next in-client report is
attributable: gate vs target vs unknown distance vs failure burst vs quarantine.

## Red/green evidence

New/re-cut pins (red before the fix where the behaviour existed, green after):

| Area | Suite | New evidence |
|---|---|---|
| A-1 | `tests/swing_source_state.lua` §6/§12/§16 (183 → 188 checks) | first-reject notice once; zero/non-numeric/secret duration recovers at the equipped speed; no readable speed still rejects; `speed_fallbacks`/`first_reject_notice` in diag |
| A-2/R1 | `tests/main_init_state.lua` §10 (re-cut) | terminal failure + disabled poll still run visibility AND alpha and re-arm at 0.05 s; a throwing visibility/alpha pass is counted and the heartbeat survives |
| A-3/A-4 | `tests/main_init_state.lua` §21 | unreadable read keeps last value, readable 0 clears; world entry re-probes; ranged START proves the weapon + builds the hand; ranged window uses the sync cycle |
| A-2 immediate | `tests/main_init_state.lua` §21 | ranged START/UPDATE/shot receipt and hunter autorepeat events each open the bar in the same event; vendored UPDATE is not promoted |
| A-4 | `tests/hunter_state.lua` §W | numeric probe id; forced event probes; throttled tick probe; clock-rewind re-probe; tick backstop |
| Red zone | `tests/hunter_state.lua` §W | disabled/absent/throwing zone never hides the bar, rewrites the swing state or stops the cast bar |
| B-5/B-6/B-7 | `tests/weave_bar_state.lua` (105 → 140 checks) | unknown face shown/latched; 24 consecutive throws do not quarantine; a success resets; 25th quarantines but keeps driver+paint; window retry recovers; diag reasons |
| A-1 crossfire | `tests/engine_matrix_state.lua` (110 checks) | forever payload: zero/non-numeric duration falls back when a readable speed exists (START with that speed, `valid_swings`++, no reject), rejects when no speed is readable |
| guards | `tests/wiring_check.lua` | 2 stale ACCEPTED rows deleted (START/UPDATE now carry the init guard); 0 stale accepts |

## Mutation proofs (17/17 killed)

On an isolated `/tmp` copy (Media/docs/.git excluded; pristine restored after each case;
restored copy re-run green). Each mutation reverts ONE new guard and must make its owning
suite red.

| # | Mutation | Killed by |
|---|---|---|
| M1 | secret swing-type guard deleted | source contract pin (`is_restricted(swing_type)` presence) |
| M2 | equipped-speed cycle recovery removed | zero/non-numeric recovery pins |
| M3 | disabled poll skips visibility/alpha | "disabled poll still runs the visibility pass" |
| M4 | heartbeat re-arm skipped when disabled | "terminal failure still arms the heartbeat" |
| M5 | visibility pass unguarded | "throwing visibility pass never escapes" |
| M6 | unknown weapon read → `or 0` | "unreadable read keeps the known weapon" |
| M7 | world-entry re-probe removed | "world entry re-probes the weapons once" |
| M8 | engine-receipt weapon proof removed | "the START proves the ranged weapon" |
| M9 | hunter-sync cycle fallback removed | "the sync cycle covers the window" |
| M10 | weave init unguarded | B-1 init-abort pins |
| M11 | ranged START immediate visibility removed | "START opens the bar in the same event" |
| M12 | auto-repeat probe back to name token | numeric-id pins |
| M13 | tick probe throttle removed | throttle pins |
| M14 | class-tick backstop removed | tick-backstop pin |
| M15 | unknown distance hides again | B-5 visible/labelled pins |
| M16 | quarantine permanent again | B-6 armed/last-paint pins |
| M17 | `diagnostic_text` returns "" | B-7 token pins |

M1 is additionally a deliberate honesty note: plain Lua has no secret values, so the
*semantic* throw cannot be reproduced offline; the sandbox therefore pins the guard at
source level in addition to the behavioural no-throw/fallback legs.

## UNVERIFIED — in-client only (nothing below is claimed fixed)

1. **Whether a skipped Auto Shot is a rejected payload or a missing event.** `/st diag`
   now shows `swing source payload_rejects=… unknown_type=… malformed_duration=…
   speed_fallbacks=…` plus `swing_ranged=start/update/stop` and `swing_last=`. One fight
   with a missed shot identifies which counter moved (audit V1/V6).
2. **`C_Spell.IsAutoRepeatSpell(75)` vs the name form on 1.60.1** (audit V2). If the
   numeric form answers on Forever, the ranged activity backstop now works; the name form
   is retained only as compat's pcall fallback.
3. **Whether `UNIT_SPELLCAST_SUCCEEDED(75)` fires per Auto Shot** (audit V5): the shot
   receipt is a second, independent path; `/st diag`'s `src=` distinguishes
   `forever` vs `shot`.
4. **`checkedDistance` behaviour on the operator's targets** (audit V3): the unknown face
   is now visible, so the next report can say whether the distance is the gate.
5. **`has_weapon` trigger**: a restricted `UnitRangedDamage`/`UnitAttackSpeed` read on
   Forever is the audit's V4 story; the code now degrades to "keep the last value" so the
   trigger can only be observed in-client (`/st diag` hand line). Not re-proven here.
6. **Red zone visual behaviour** is unchanged by design (audit §8 PASS + new pins); the
   in-client overlay appearance is unchanged and unobserved by this desk.
7. **`UNIT_TARGET("player")` vs `PLAYER_TARGET_CHANGED` on Forever** (audit A-7) — not
   fixed, see follow-ups.

## Follow-ups filed, not done (outside this desk's verdict)

- **A-5 (engine divergence on combat exit)**: `swing_source.on_combat_changed` clears
  every live cycle on combat exit while both comparators keep the cycle; the audit
  calls this a shortened/mis-timed animation. Changing it needs the operator's contract
  decision, and `tests/swing_source_state.lua` §4 pins the current shape.
- **A-7**: the addon never registers `PLAYER_TARGET_CHANGED`; `has_attackable_target` is
  only written by `UNIT_TARGET("player")`. The default `either` show rule masks it in
  combat. Needs an operator/Lead decision (new event registration = behaviour change).
- ~~**`tests/secret_guard_state.lua` §8 is stale as a *representation* of
  `check_weapons`**~~ — **CLOSED in the follow-up pass** (Lead scope extension): §8 now
  pins the new contract through a local `weapon_decision` mirror plus source-shape pins
  (readable number moves the flag; a secret read keeps the previous value; a readable 0
  still clears; the old `or 0` shape must be absent for both hands), while keeping every
  wrapper assertion. `lua5.1 tests/secret_guard_state.lua` = **447 checks, 0 failures**;
  a /tmp revert of `check_weapons` to the old `or 0` shape fails exactly those 2 source
  pins (mutant exit 1).
- **`tests/bars_state.lua` hide-reason behavioural pin** (filed by `ui-truth-diag`) is
  still owed; `bars_state.lua` is the bars-perf desk's file.
- **`bench/bars_perf_audit_2026-11-06.md` on disk is a 17-line summary** without the
  §4/§5 the dispatch cited (the full census is in `desks/perf-audit/journal.md`). Not
  this desk's file; recorded for the Lead.
- **Version fields** are 2.2.0 (rogue write); Lead restores 2.1.8. This desk left them
  untouched.
