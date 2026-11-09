# Filing note (orchestrator, 2026-10-19)
Lane `feature-hunter` (session ses_eac70cf7dffdBxC3PCwnSi5SRg) completed read-only but had no write-capable tool in its session, so it could not create this file, `desks/feature-hunter/journal.md`, or its signal JSON. Body below is the lane's returned text verbatim. Treat this file as the lane's done-signal content.

---
## Silent Failure Hunt — File Content for `bench/feature_hunter_audit_2026-10-19.md`

### Silent Failure Hunt: Feature error paths — swing/twist/weave/guide/HUD/range/GCD/Retail-Forever engines

#### Scope

**Reviewing:** In-tree audit surface per `bench/briefs/brief_feature-hunter_2026-10-19.md`: `main.lua`, `bars.lua`, `compat.lua`, `swing_source.lua`, `twist.lua`, `weave.lua`, `nextaction.lua`, `nextaction_ui.lua`, `classes/druid.lua`, `classes/hunter.lua`, `classes/paladin.lua`, `classes/shaman.lua`, `classes/warrior.lua`, `hud.lua`, `practice_ui.lua` (+`practice.lua`), `enemy_swing.lua`, `weave_range.lua`, `diag.lua`.

**Files reviewed:** 19

**Error-handling and fallback locations reviewed:** ~52 (grouped where one failure path spans wrapper + consumer)

**Suspicious patterns identified:** 17

**Disposition counts:** 6 confirmed defects, 7 requiring justification, 4 justified exceptions (4 positive patterns recorded separately)

Bench-read first (per brief §Context): `desks/journal.md` (35 steps 0 failed, luacheck 2/0 floor, all lanes done), `bench/lessons.md` (never gate on `st.is_mainline` alone; rumor vs CONFIRMED; no default-visible change), `bench/oracle_audit_2026-10-17.md` (READY-WITH-FIXES, R1–R4 + N1–N6), `bench/verify_bank.md` (CONFIRMED ids + UNCONFIRMED list), `hands-up.md` (HU-1..HU-3 defer/proceed, HU-4 resolved-by-fix). This lane extends — does not re-derive — those answers.

Cross-checked oracle fixes in-tree: R2 scan no longer early-breaks (`compat.lua:519-521`), R3 CLEU badge notice present (`classes/paladin.lua:1306-1316`), R1 name fallback present (`classes/paladin.lua:623-640`, `twist.lua:83-88`), R4 partially closed (`classes/paladin.lua:1051` now `== true`; hunter consumer not re-verified this lane — left as pointer).

#### Critical Issues — Must Fix

*None confirmed. The strongest rubric-CRITICAL candidate (inert stub masquerading as a live swing engine) carries a one-time chat notice plus a `diag` engine field, so it is graded HIGH, not CRITICAL. See H1.*

#### High Severity Issues

**Issue H1: Inert swing stub reports a healthy-looking 1 s swing on a dead engine**

**Severity:** HIGH

**Disposition:** CONFIRMED DEFECT

**Location:** `main.lua:19-28` (`make_swing_stub`), `main.lua:40-42`, `main.lua:375-378` (deadline rescue); consumed by `main.lua:627-635`, `swing_source.lua:249-257` (same idle shape)

**Pattern:** Production fake masking dependency failure / false success for core operation

**Current Code:** `SwingTimerInfo` returns `1, GetTime()+1, GetTime()` when no engine exists; `ST.swing_engine="inert-standin"`.

**Hidden Errors:** Vendored lib absent (Retail) or never-ready engine (deadline rescue). Caller (`init_timers`, bars, guide gather) cannot distinguish "idle, no swing yet" from "engine dead for the session" — both read a plausible 1 s cycle.

**Impact:** Casual: bars sit full/idle, user waits for a swing that never comes. Top-level: `nextaction` Retail short-circuit (`nextaction.lua:354-365`) hides the guide, but non-Retail stub states (e.g. a Forever engine that never reports ready) still feed the pure engines plausible timings — wrong rotation/twist-window advice at ms scale with no on-bar signal. The only notice is one chat line (`main.lua:606`) plus `/st diag` — both missable mid-combat/reload.

**Evidence:** Read `main.lua:19-42, 363-382, 602-614` (proven offline). No bar-level degraded state found by grep (`bars.lua` has no `swing_engine` read).

**Required Fix:** Surface the degraded engine where the swing is read, not only in chat/diag — e.g. a per-hand `engine_dead` flag the bar/guide can render (dim + "engine offline" text), or make the stub return `nil`-shaped idle the guide already treats as unknown. Smallest conceptual change: stub returns `nil, nil, nil` (or a sentinel) and `init_timers`/gather render that as unknown instead of a 1 s cycle.

---

**Issue H2: Bar-tick class hook and zone draws run unprotected — one throw freezes the swing bar**

**Severity:** HIGH

**Disposition:** CONFIRMED DEFECT

**Location:** `bars.lua:615-624` (`class.on_bar_update`), `bars.lua:504-529` (`update_zones` → `list[i].draw_fn(ctx)`); header comment `bars.lua:422` explicitly declines `pcall`

**Pattern:** Missing isolation on a hot, timing-critical path

**Current Code:** `class.on_bar_update(self, hand)` and zone `draw_fn(ctx)` called directly in `onupdate_common` (20 Hz-class cadence).

**Hidden Errors:** Any error in paladin/shaman/hunter/druid/warrior `on_bar_update`, `nextaction_ui.update` (driven from the same hook), or a registered zone aborts the rest of `onupdate_common` for that tick — including the LDB feed — and, if the error repeats, freezes bar width/text every frame. No log, no counter, no per-hand quarantine.

**Impact:** Top-level: a single class-module bug (e.g. a nil texture, a bad `GetSpellInfo` return on a new family) stops the reaction-critical visual the player is timing casts to. Casual: frozen bar reads as "lag", not "addon error". Debug-hostile: no breadcrumb identifies which hook threw.

**Evidence:** Read `bars.lua:422, 504-529, 612-632`; `nextaction_ui.lua:706-713` confirms the guide is driven from the same hook. `diag.tick_sites` counts ticks but does not record hook errors.

**Required Fix:** Isolate, don't silence: wrap each `on_bar_update` + each zone `draw_fn` in a guarded call that (a) lets the bar fill/text still paint, (b) records the first error per session (chat once + `diag` counter), (c) optionally disables the offending hook/zone after N consecutive throws. Never swallow without the counter.

---

**Issue H3: `callback_event_handler` fan-out is unguarded — one bad handler breaks the dispatching callback**

**Severity:** HIGH

**Disposition:** CONFIRMED DEFECT

**Location:** `main.lua:779-791` (`ST.callback_event_handler` → `ST[event](ST, event, ...)`); callers `main.lua:340-357, 389-393`, `bars.lua` lib callbacks

**Pattern:** Broad dispatch without containment

**Current Code:** Direct `ST[event](ST, event, ...)` with commented-out debug prints, no guard.

**Hidden Errors:** `LATENCY_CHANGED`, `GCD_*`, `SWING_TIMER_*` lib callbacks share this path. A throw in `GCD_OVER`/`on_latency_update`/swing handlers propagates back into the library's `Fire`, potentially aborting other listeners or the library's own bookkeeping for that event.

**Impact:** Intermittent Init-window-adjacent crashes already guarded individually (`GCD_OVER`, spellcast handlers check `interfaces_are_initialised`) show the team knows this path throws — but the fan-out itself has no containment. Worst case: GCD/latency state stops updating while bars keep painting stale markers.

**Evidence:** Read `main.lua:779-791, 801-820, 845-858`. Contrast with the per-handler init guards — the guards prove throwability, the dispatcher has no backstop.

**Required Fix:** Guard the fan-out with per-event error capture (log once + `diag` count), preserving the existing per-handler init guards. Keep the handler error visible; never silently resume without the counter.

---

**Issue H4: Missing-data cast time degrades to instant (0) — the weave marker then claims "always safe"**

**Severity:** HIGH

**Disposition:** CONFIRMED DEFECT

**Location:** `weave.lua:199-211` (`get_effective_cast_time`); catalogue miss path `classes/shaman.lua:314-324, 355-382` returns `nil` catalogue → base cast unknown

**Pattern:** Silent null/default substitution misrepresenting an unsuccessful read

**Current Code:** `base` non-number/`<=0` → `return 0`; `mw` non-number → `1`. `get_marker_fraction` with cast 0 → marker ≈ 1.0 (whole swing safe).

**Hidden Errors:** Unresolved weave catalogue entry (unknown rank, missing id on Forever/SoD, `GetSpellInfo` nil), missing haste/MW multiplier. The pure layer cannot tell "instant by buff/stacks" from "I never resolved the spell".

**Impact:** Top-level shaman: breakpoint marker pinned at swing end + `can_prompt_weave`/`get_spell_position_state` reads "ready" for a hard-cast LB/CL that actually clips — the exact mistimed-cast the assist exists to prevent. Casual: learns the wrong window. The failure is invisible (marker still draws, spark still travels).

**Evidence:** Read `weave.lua:199-221, 130-154`; `classes/shaman.lua:291-309` (`nil` on unresolved). No `nil`-propagation: 0 is a valid instant-cast signal AND the missing-data signal.

**Required Fix:** Separate the signals: return `nil` (unknown) for unresolvable base cast; make `get_marker_fraction`/`get_spell_position_state` treat `nil` effective-cast as unknown → hide/dim the marker (the "never draw on a guess" discipline `get_cast_zone_bounds`/`get_totem_twist_remaining` already follow) instead of rendering instant.

---

**Issue H5: `swing_source` drops unknown/malformed `PLAYER_SWING` payloads without a trace**

**Severity:** HIGH

**Disposition:** CONFIRMED DEFECT (downgraded from CRITICAL only because the engine-inert path is probed; the payload path is not)

**Location:** `swing_source.lua:154-170` (`on_player_swing` early returns), `swing_source.lua:172-212` (`on_unit_attack_speed` silent keeps)

**Pattern:** Empty-effective catch / swallowed validation failure on the sole Forever swing feed

**Current Code:** `if not hand then return end`; `if type(swing_duration)~="number" or <=0 then return end`; throwing/secret/stale `UnitAttackSpeed` → `return` keeping the old cycle.

**Hidden Errors:** Unknown future `Enum.PlayerSwingType` value, renamed payload order, `nil` duration on a client patch, persistently secret/stale attack speed. All keep the last cycle (or no cycle) with zero chat/diag footprint.

**Impact:** Forever-only but total: the swing bars freeze or run on a stale speed while twist band + next-action guide (`st.family=="FOREVER"` runs the archived tree, `nextaction.lua:87-88`) keep prompting off the stale schedule — ms-scale mistwists with confident UI. No `diag` engine-health signal distinguishes "no swings yet" from "payloads rejected for N seconds".

**Evidence:** Read `swing_source.lua:133-170, 172-212, 249-257`. `diag` reports only the engine *name*, not payload-reject counts.

**Required Fix:** Count payload rejects + speed-read keeps (session counters surfaced in `/st diag` verbose line); optionally one-time chat notice on sustained rejects (e.g. >5 s with combat + no valid swing). Never change the keep-old-cycle behavior — only make it observable.

---

**Issue H6: Spellcast-lifecycle fan-in lacks the init guard its siblings carry**

**Severity:** HIGH

**Disposition:** REQUIRES JUSTIFICATION (graded HIGH because the reached code touches bar visuals)

**Location:** `main.lua:1079-1105` (`UNIT_SPELLCAST_START/DELAYED/STOP/INTERRUPTED/FAILED/CHANNEL_*` → `class_on_spellcast_event`); contrast `main.lua:1051-1073` (`FAILED_QUIET`/`SUCCEEDED` guard on `interfaces_are_initialised`)

**Pattern:** Inconsistent guard — expected failure (init-window cast) handled in two handlers, unhandled in seven

**Current Code:** Seven thin handlers forward unconditionally; `class_on_spellcast_event` (bars-adjacent class hooks recolour the bar per `UNIT_SPELLCAST_SUCCEEDED` comment `main.lua:1063-1065`) may index visuals frames that do not exist inside the ~5 s init window.

**Hidden Errors:** Cast/channel events firing between login and `init_libs` (reload mid-cast, init deadline path). If any class `on_spellcast_event` touches `get_visuals_frame`/textures unguarded, this is a login-time nil-index throw funneled through the unguarded dispatcher (H3) — silent bar death or Lua error with no breadcrumb pointing at the missing guard.

**Impact:** Login/reload crash or dead bar on exactly the sessions the deadline path already makes fragile. In-client symptoms mimic H2/H3 (frozen bar) but the fix is one guard.

**Evidence:** Read `main.lua:1048-1105`. `class_on_spellcast_event` body not located in `main.lua` (likely `bars.lua`/class mixin) — **UNCONFIRMED** whether it self-guards. Evidence needed: point at the `class_on_spellcast_event` definition and confirm an init guard or a visuals-nil guard.

**Required Fix / question for owner:** Either add the same `interfaces_are_initialised` early-return to the seven thin handlers, or cite the callee-side guard that makes it redundant.

---

#### Medium Severity Issues

**Issue M1: Range-poll dead-man disables range for the session on the first throw**

**Severity:** MEDIUM

**Disposition:** CONFIRMED DEFECT

**Location:** `main.lua:1399-1425` (`rf_update` `pcall` → `disable_range_checking`), `main.lua:1333-1342`, `main.lua:1344-1350`

**Pattern:** Retry exhaustion without a surfaced terminal outcome (single notice, permanent disable)

**Hidden Errors:** Any transient throw inside the poll (`melee_range_checker_func`, `GetRange`) — including the documented classic-only-global risk on Retail/Forever (`main.lua:1399-1404`) — permanently stops the 0.05 s loop for the session.

**Impact:** Range text/dim freezes or blanks; hunter H4 pre-cast gate (`nil=allow`) silently flips to allow-all. One chat line is the only signal; `/st diag` shows `lrc=fallback` (good) but the bar gives no degraded-range affordance.

**Evidence:** Read `main.lua:1371-1425`. Proven offline that the `return` after `disable_range_checking()` ends all retries.

**Required Fix:** Bounded retry with backoff (e.g. N attempts, then session-disable), or re-arm on next `CHECKERS_CHANGED`/target change. Keep the one-time notice; add the retry count to `diag`.

---

**Issue M2: Range-checker retry loop never exhausts and never logs**

**Severity:** MEDIUM

**Disposition:** CONFIRMED DEFECT (companion to M1 — the two branches have opposite failure modes)

**Location:** `main.lua:1381-1398` (nil melee checker → `C_Timer.After` re-arm + `set_bar_visibilities`)

**Pattern:** Silent unbounded retry

**Hidden Errors:** Checkers that never resolve (incompatible client, library stripped). Loop re-arms every 0.05 s forever, calling `set_bar_visibilities` each lap, with no log, no `diag` counter, no deadline.

**Impact:** Invisible timer churn for the whole session; masks the same "range will never work here" state M1 reports loudly. Perf-trivial per lap, but unbounded and unobservable.

**Evidence:** Read `main.lua:1371-1398`. No counter, no cap, no shared path with `disable_range_checking`.

**Required Fix:** Cap the laps (or fold into the deadline state: after K laps, `disable_range_checking()`), with the same one-time notice + `diag` flag.

---

**Issue M3: `SPELL_DAMAGE` with an unrecognised payload shape silently consumes nothing**

**Severity:** MEDIUM

**Disposition:** REQUIRES JUSTIFICATION

**Location:** `classes/paladin.lua:623-647`, `twist.lua:67-88`

**Pattern:** Silent non-match on an evolving external contract (Anniversary CLEU, oracle R1)

**Current Code:** `sid` number → id table; `sid` string → name table; else `sname` string → name table; anything else → `success=false`, attempt stays pending until the next swing recomputes it.

**Hidden Errors:** A third payload shape (nil id + nil name, table payload, localized name not yet resolved because `resolve_soc_proc_names` returned nil and the retry window hasn't elapsed).

**Impact:** Twist score sits at 0% with attempts climbing — reads as "player missing twists" when the addon is actually blind. On Anniversary this is the exact R1 risk; on Forever the R3 notice covers it, on Anniversary nothing does.

**Evidence:** Read `classes/paladin.lua:555-575, 623-647`. Partial mitigation verified (name fallback + retry at `SOC_PROC_NAMES_RETRY_S`). **UNCONFIRMED:** whether a sustained zero-success run surfaces anywhere (no counter/diag line found).

**Required Fix / question:** Add a session `twist_unmatched_payloads` counter to `/st diag` (or reuse the H5-style reject counter), or document why the badge alone suffices.

---

**Issue M4: Twist band hides engine/mirror failures as "no twist now"**

**Severity:** MEDIUM

**Disposition:** REQUIRES JUSTIFICATION

**Location:** `classes/paladin.lua:1330-1338` (early-hide ladder), `classes/paladin.lua:608` (`parse_seals` per swing)

**Pattern:** Degraded-state invisibility (fallback hides rather than signals)

**Hidden Errors:** `d.speed/ends_at/start` missing (stub/dead engine), `parse_seals` returning 0 on a broken aura read, `is_full` stuck true after `SWING_TIMER_STOP` without a matching start.

**Impact:** Band hidden is the normal "don't twist" look — a dead swing feed and a correct "single seal" state are visually identical. Player stops trusting the band, or trusts a stale absence.

**Evidence:** Read `classes/paladin.lua:1330-1344`. The R3 badge notice covers *scoring*, not the *band*. **UNCONFIRMED:** whether `parse_seals` failures are distinguishable from genuine 0/1-seal states.

**Required Fix / question:** Cite the aura-mirror failure signal (if any), or render a distinct "seal data unknown" band state when `d` is unusable vs genuinely single-sealed.

---

**Issue M5: Secret-regime lust reads degrade to "no window" with no on-bar signal**

**Severity:** MEDIUM

**Disposition:** REQUIRES JUSTIFICATION (contract-compatible by design; player-visible cost remains)

**Location:** `compat.lua:440-485` (whole-entry secret degrade), `compat.lua:511-540` (scan continues past secrets — R2 fix verified), consumers `classes/paladin.lua:1014-1051`, `classes/hunter.lua` H2 (not re-read this lane)

**Pattern:** Intentional fallback whose operational cost lands on the player silently

**Hidden Errors:** Secret HELPFUL aura rows (Midnight restriction) hiding Bloodlust/Heroism; restricted cooldown/power reads feeding the guide `nil`s that withhold fillers/CS cues.

**Impact:** Under a real Bloodlust the twist window does not narrow (P3) / Steady-spam cue does not fire (H2) — the player plays the un-hasted rotation through a lust. `/st diag` `secrets` line reports the regime (good), but the bar/guide show confident un-hasted advice with no degraded-mode tint.

**Evidence:** Read `compat.lua:440-540`; `bench/oracle_audit_2026-10-17.md` R2 (fixed shape verified in-tree). Consumer-side degraded rendering **UNCONFIRMED** this lane.

**Required Fix / question:** Confirm or add a lust-unknown affordance (e.g. lust icon dimmed with "?" while `C_Secrets` reports aura secrecy), or record the accepted residual ("lust may miss under secret regime; diag documents it") as a justified exception.

---

**Issue M6: `nextaction` archive defaults + stale-input reuse can prompt confidently on missing data**

**Severity:** MEDIUM

**Disposition:** REQUIRES JUSTIFICATION

**Location:** `nextaction.lua:367-396` (speed 3.0 / G 1.5 / window 0.4 / `cs_delay_max` 0.9 defaults; Retail short-circuit `354-365`), `nextaction_ui.lua:680-696` (`inputs = provider.gather(...)`, non-table → reuse `ui.inputs`)

**Pattern:** Default returns masking unsuccessful reads; stale-state reuse

**Hidden Errors:** `speed`/`G`/`gcd_remaining`/`seal`/`cs_remaining` nil (secret cooldowns, unknown spell book, dead engine feeding 1 s stub speed); `gather` returning non-table on an exception path.

**Impact:** Wrong rotation label (`calculate_rotation` thresholds are speed-sensitive), wrong reseal deadline, `filler_kind` withheld or prompted on `999`-sentinel confusion. The guide frame still draws — reads as advice, not as "waiting for data". Retail is correctly inert; every other family prompts on defaults.

**Evidence:** Read `nextaction.lua:345-406, 541-572`; `nextaction_ui.lua:642-703`. The `999`-sentinel discipline is documented and consistent (good), but the *all-missing* shape collapses to archive defaults with no unknown flag on `out`. **UNCONFIRMED:** which `gather` fields can actually arrive nil live (needs paladin provider read `classes/paladin.lua:1529+` consumer trace — out of this lane's re-read budget; proctor pointer below).

**Required Fix / question:** Either thread an `inputs_unknown` bit through `out` (guide renders "…" instead of an action when speed/G/seal are all defaulted), or cite the provider-side guarantee that gather never emits all-defaults live.

---

**Issue M7: Enemy-swing `2.0` fallback + frozen-bar silence on a dead clock**

**Severity:** MEDIUM

**Disposition:** REQUIRES JUSTIFICATION

**Location:** `enemy_swing.lua:113-128` (`FALLBACK_SPEED = 2.0`), `enemy_swing.lua:333-345` (`start_cycle`), `enemy_swing.lua:435-469` (`on_update` silent `return`s)

**Pattern:** Fallback chain without explanation; missing diagnostic context

**Hidden Errors:** `read_target_speed()` nil (absent client / restricted / non-positive) with no cached cycle → every new cycle times at 2.0 s regardless of the real weapon; `now()` nil (broken `compat` clock) → `on_update` returns leaving the last fill + stale text painted indefinitely.

**Impact:** Hostile-target bar shows a confident 2.0 s cadence that is pure guess — the player times interrupts/peels to a fiction. Clock-nil freeze is worse: a live-looking bar that never moves again, with no `diag` footprint (`enemy_swing` has no counters).

**Evidence:** Read `enemy_swing.lua:272-285, 333-345, 435-469`. Reference parity is documented (2.0 is the reference fallback — good provenance), but the *rendered* bar does not distinguish fallback from measured. **UNCONFIRMED** in-client: `UnitAttackSpeed("target")` fidelity per family (already flagged `enemy_swing.lua:40-42`).

**Required Fix / question:** Render fallback cycles distinctly (hatched/dim + no tenth text, or keep the target-name text instead of a fake countdown), and hide (not freeze) when `now()` is nil. Or record "2.0 fallback is displayed as-is by design" with the in-client fidelity check as the acceptance proof.

---

#### Issues Requiring Justification (not already graded above)

1. **Hunter lust nil-semantics (oracle R4 remainder).** `classes/paladin.lua:1051` now gates `st.lust_supported == true` (closed-on-unknown). Hunter H2 consumer (`hunter.lua:1067` per oracle) was `if st.lust_supported and ...` (nil→off) — same observable outcome today, but the frozen-contract doc should name one rule. *Needs:* hunter-side line reference + standardisation on `== true`, or a contract note that both spellings are intentionally kept. (Proctor pointer: confirm during coverage pass.)
2. **`class_on_spellcast_event` callee guard (H6's missing half).** *Needs:* file:line of the definition + confirmation it early-returns pre-init / on nil visuals. One-line pointer suffices.
3. **Paladin provider nil-field audit (M6's missing half).** *Needs:* for each frozen input (`speed`, `G`, `seal`, `cs_remaining`, `filler_remaining`, `jotc_remaining`, `target_count`) whether the gather can emit nil live and what the engine renders then. The `998`-vs-`999` and `target_count` presence rule are already documented (`classes/paladin.lua:1497-1528`) — extend, don't re-derive.
4. **Shaman catalogue-retry observability.** `classes/shaman.lua:319-324, 368-382` retry silently; weave markers stay hidden while unresolved. *Needs:* confirm a `diag`/chat footprint exists for sustained catalogue miss (esp. Forever ids), or accept hidden-with-retry as designed (weave markers hidden = safe direction, unlike H4's instant-0).
5. **`hud.lua:514` probed CLEU registration.** `pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")` — on probe failure the trinket-refresh path silently loses its combat-log trigger. *Needs:* confirm the fallback trigger (cooldown poll?) that keeps trinket swipes live, or one line that the swipe simply goes stale (and the staleness is acceptable because…).
6. **`practice_ui.lua:396-407` combat-retry loop.** Re-arms every 1 s while locked down; unbounded but cheap. *Needs:* nothing — flagging for completeness; accept-by-inspection unless proctor finds a re-entrancy (double `init` while a session runs).
7. **`weave_range.lua:238-241` hide-on-unknown.** Hiding instead of guessing is the right call; the residual is discoverability (feature on, no target/range → nothing drawn, reads as broken). *Needs:* confirm the options copy already sets this expectation, or accept as-is.

#### Audited Justified Exceptions

- **E1. `diag.lua` never-throws discipline (`diag.lua:56-82, 121, 362, 389-416`).** Suppressed: every probe error, rendered as `?`/`unavailable`. Accepted: the module's contract is PRINT-ONLY and never-throws (header + `tests/diag_state.lua` pins); a throwing diagnostic would be worse than a `?` line. Audience: operator. The `MAX_LINES` cap + per-line `pcall` keep one bad field from costing the report.
- **E2. `compat.lua` whole-entry secret degrade (`compat.lua:440-485, 543-557, 725-753, 996-1019`).** Suppressed/transformed: secret fields → nil-entry / zero-shape / unknown. Accepted: documented whole-or-nothing rule with per-wrapper rationale; exact no-op where the probe is absent; `diag` `secrets` line (`diag.lua:344-381`) makes the regime visible; every caller contract treats the degraded shape as unknown-never-guess. Audience: operator (diag) + caller (nil-safe branches). Residual M5 (lust UX) tracked separately.
- **E3. Family-gated inertness without frames/events (`swing_source.lua:63-64, 263-291`; `enemy_swing.lua:599-643`; `hud.lua:437, 537-548`; `nextaction.lua:354-365`; `nextaction_ui.lua:290-311`).** Suppressed: entire features on off-family clients (no frame, no event, no read). Accepted: probe-first family gates (never `is_mainline`-alone), documented per-module, `/st diag` reports family/engine/module presence. The Retail stand-in notice (`main.lua:605-607`) and R3 twist notice (`classes/paladin.lua:1306-1316`) are the visible-degradation pattern done right.
- **E4. Intentional early-return guards (combat-exit teardown, aura/unit filters, practice-owns-state).** Sampled: `classes/paladin.lua:1454-1492` (HU-4 fix — guarded glow stops, state reset safe anywhere), `main.lua:769-777, 1029-1049` (unit/init filters), `classes/paladin.lua:578-587` (practice owns twist state), `enemy_swing.lua:476-515` (inactive/off-feature cheap returns). Accepted: narrowly scoped, commented, state-consistent (teardown zeroes latches; filters return before touching visuals). Audience: none needed — these are non-failures by contract.

#### Positive Findings

- **R2/R3 closures are exemplary silent-failure repairs.** The scan walk (`compat.lua:516-539`) names the anti-pattern ("No early break (R2)") at the exact lines; the CLEU badge (`classes/paladin.lua:1306-1316`) turns a silently-0/0 widget into a one-line explanation gated on the compat probe, not on `is_mainline`. Both are the visible-degradation standard this audit grades against.
- **`enemy_swing` and `weave_range` document their unknowns instead of hiding them.** `enemy_swing.lua:40-42`, `weave_range.lua:32-36` mark in-client confirmations NEEDED; pure helpers return `nil` (never a guess) and callers hide rather than fabricate (`enemy_swing.lua:143-171`, `weave_range.lua:238-254`). M7 asks only for fallback-vs-measured rendering, not for a redesign.
- **`weave.lua` "never X on a guess" discipline is consistent.** `get_spell_position_state`/`can_prompt_weave` (unknown→`wait`), `get_icd_remaining` (unknown→`nil`), `is_dw_desynced`/`should_hold_stormstrike` (strict numerics), `get_totem_twist_remaining`/`get_magma_remaining` (unknown→`nil`). H4 is the one place the same module breaks its own rule (0 = instant = unknown) — which is why it is HIGH.
- **`main.lua` init-deadline + `diag` self-report is honest infrastructure.** The deadline (`main.lua:363-382`) records `init_deadline_fired`, lifts late LRC checkers (`340-351`), prints once per dead path, and `diag.flags_line`/`lrc_state` re-expose all of it greppably. H1/M1/M2 ask for *rendering* the dead-engine state on the bars, not for new plumbing — the plumbing is already there.

#### Summary

| Severity | Count | Action |
|---|---|---|
| CRITICAL | 0 | — |
| HIGH | 6 | Fix or answer before merge (H6 may close as justified with one callee cite) |
| MEDIUM | 7 | Improve when practical; M3–M7 each name the single evidence line that closes them |

**Unresolved justification cases:** 7 (H6 + M3–M7 substantive; + 7 quick pointers listed under "Issues Requiring Justification", several overlapping)

**Justified exceptions:** 4

#### Verdict: NEEDS FIXES

H4 (instant-on-missing weave cast) and H5 (untraced Forever payload rejects) can mistime real casts with confident UI — both need a fix or a counter before the owner test session, not after. H1/H2/H3 are structural (fake-healthy stub, unguarded hot dispatch) with the repair direction named per issue. No CRITICAL (no data-loss/corruption path found), and the oracle R1–R3 closures verified in-tree. Coverage pointer for the proctor lane: `classes/hunter.lua` H2 lust gate line + `class_on_spellcast_event` definition + paladin provider nil-field matrix (M6) were not re-read here — one line each closes R4/H6/M6.

*Limitations:* read-only (no probes; every UNCONFIRMED above is a real in-client check, not a hedge). `desks/feature-hunter/` creation, `desk-journal` append, and `signal-write` were unavailable from this session (no write/signal tools) — orchestrator to record.
