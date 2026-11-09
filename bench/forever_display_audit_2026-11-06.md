# WoW Forever display pipeline audit — 2026-11-06

Desk: `desks/forever-audit` (read-only). Baseline: WoW Forever = Camelot 1.60.1,
Interface 16001, `WOW_PROJECT_CAMELOT = 18`, Mainline-code (`st.is_mainline == true`,
no classic CLEU). Client facts are cited from `origin/forever` (`eac30af59 1.60.1
(70790)`) as `origin/forever:path:line`; addon facts as `file:line` in this tree.

This report supersedes the shallow draft `bench/swedge_addon_audit_forever_display_2026-11-06.md`
(a different desk's file; **not edited** by this desk). See §11 for the two corrections.

---

## 0. Executive summary

| # | Symptom | Likely root cause(s) in this tree | Severity | Confidence |
|---|---------|-----------------------------------|----------|------------|
| C-1 | Power bar absent on Forever | Secret `UnitPower`/`UnitPowerMax` are degraded to `nil` by compat; `power_bar.lua` hides on `no-value` and paints with texture arithmetic, so the only supported path (raw secret → real `StatusBar`) is not implemented. | HIGH | HIGH (code path), HIGH (client evidence from operator) |
| A-1 | One Auto Shot sometimes not displayed | The Forever engine's `PLAYER_SWING` START can be rejected (`malformed_duration`/`unknown_swing_type`) or never delivered for a cycle; the rejection is silent for a single shot (notice only after 5 s in combat), and the bar simply keeps the previous cycle. | HIGH | MED (code path certain, trigger needs in-client `/st diag`) |
| A-2 | Same, session-wide variant | The visibility driver (`rf_update`) can stop permanently: only `update_range_state` is pcall-wrapped, the pass (`set_bar_visibilities`) and `handle_oor` are outside it, and the re-arm is the last statement. A throw there ends the poll with no `rf_disabled` and no notice; a bar hidden at that moment never reappears. | HIGH | HIGH (defect), UNVERIFIED (trigger) |
| B-1 | Horizontal range bar worked, then stopped | `weave_range.init` is called in `post_init`'s unguarded tail; an earlier throw means the frame/driver never exists, with no retry. Second stop path: the driver self-quarantines after 25 throws (removes its own OnUpdate). Third: `UnitDistance == nil` (client `checkedDistance == false`) hides by contract. | HIGH | HIGH (code), UNVERIFIED (trigger) |
| A-3 | Ranged/offhand hands can silently disable | `check_weapons` reads `api.UnitRangedDamage`/`api.UnitAttackSpeed`; compat nils any secret read, and a nil is read as "no weapon" → `has_weapon=false` → `bar_is_enabled` false **and** `ensure_bar` refuses to build. Re-probed only on an equipment change. | HIGH | HIGH (code), MED (trigger) |

Two repair directions are supported by direct client evidence and should be treated as
the minimal fixes (details in §7):

1. **Power bar:** pass the raw secret through a real `StatusBar` (`SetMinMaxValues` /
   `SetValue` accept secrets from tainted code); skip text/fraction while restricted.
   `origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua:229-232`
   and `:355-358` mark both methods `SecretArguments = "AllowedWhenTainted"` with
   `SecretArgumentsAddAspect = { Enum.SecretAspect.BarValue }`, and Blizzard's own
   `origin/forever:Interface/AddOns/Blizzard_UnitFrame/Mainline/UnitFrame.lua:939-975`
   passes raw `UnitPower`/`UnitPowerMax` into them from the (tainted) unit-frame addon.
2. **Auto Shot:** make the visibility driver unkillable and the payload rejection
   observable (plus, if the client confirms it, keep the ranged receipt alive without
   the name-shaped auto-repeat probe). The red-zone/cast-bar faces are already
   display-only and must stay that way (§4.4).

---

## 1. Method and evidence base

- Read-only: no product code, tests, TOCs, bench history or git history was modified.
  Only this file, `desks/forever-audit/journal.md` and
  `desks/forever-audit/.signals/<ts>.json` are new.
- Priors read before any search: `desks/journal.md` (2026-11-03 reconcile + the
  2026-11-06 dispatch block and operator clarifications), `bench/lessons.md`,
  `AGENTS.md` (Cross-engine + Gotchas), and the three Forever desk journals
  (`forever-guide-ui`, `forever-secrets`, `release-217`). No answered question was
  re-searched.
- Every Forever API claim was checked with
  `git -C /home/sam/wow-ui-source show origin/forever:<path>` (the reference repo is
  readable with shell access; the checked-out branch is `classic_era`, so
  `origin/forever` was named explicitly on every read).
- Targeted reads/greps only; no 100 KB file was loaded whole into context.

Tree state observed while working (times local, 2026-11-06):

- `git status --porcelain`: the seven TOCs and `main.lua` are **modified** (version
  fields), plus new `bench/bars_perf_audit_2026-11-06.md`, `bench/swedge_addon_audit_forever_display_2026-11-06.md`,
  `desks/perf-audit/`, `desks/release-version/`. HEAD is `7207f80` ("release v2.1.7").
- **Version fields are out of scope for this audit and are in flight.** At read time
  (19:11Z) all seven TOCs line 6 + `main.lua:5` read `2.2.0` (uncommitted, mtime
  14:11:10); the `desks/release-version/journal.md` records the operator-approved
  **2.1.8** bump and my dispatch baseline says 2.1.7. This audit makes no version
  target claim — the version/docs desk owns it. Re-check before publishing.
- The harness (57 steps / 0 failed) and luacheck (2 warnings / 0 errors) were verified
  by the orchestrator at dispatch; this desk did not re-run the suite while parallel
  lanes were editing the tree.

---

## 2. Client facts used by this audit (all from `origin/forever`)

| Fact | Evidence |
|---|---|
| `PLAYER_SWING(swingDuration:number, swingType:Enum.PlayerSwingType)` synchronous event; `Enum.PlayerSwingType = { MainHand=0, OffHand=1, Ranged=2 }` | `Interface/AddOns/Blizzard_APIDocumentationGenerated/SwingTimerDocumentation.lua:43-52`, `:71-82` |
| `C_SwingTimer.EnableRangeCheck` / `IsTargetWithinSwingRange` exist; range check is opt-in; `IsTargetWithinSwingRange` returns nil when no check is possible (no target / not attackable / no weapon) | same file `:11-20`, `:23-38` |
| Blizzard's own swing timer consumes `PLAYER_SWING` (`swingDuration, swingType`) and only re-times presentation on combat/target/range | `Interface/AddOns/Blizzard_SwingTimer/Blizzard_SwingTimer.lua:142-170` |
| Blizzard's ranged-weapon presence probe is `UnitAttackSpeed("player")`'s **third** return (`HasRangedWeapon`), and its ranged duration is that same third return | `.../Blizzard_SwingTimer.lua:177-201` |
| `UnitAttackSpeed` returns `(attackSpeed, offhandAttackSpeed?, rangedAttackSpeed?)`, marked `SecretWhenUnitStatsRestricted` | `.../UnitDocumentation.lua:682-697`; predicate `.../SecretPredicatesDocumentation.lua:155` |
| `UnitRangedDamage` returns `(speed, minDamage, maxDamage, posBuff, negBuff, percent)`, marked `SecretWhenUnitStatsRestricted` | `.../UnitDocumentation.lua:2962-2965` |
| `UnitPower` marked `SecretWhenUnitPowerRestricted`; `UnitPowerMax` marked `SecretWhenUnitPowerMaxRestricted` | `.../UnitDocumentation.lua:2732-2739`, `:2801-2808`; predicates `.../SecretPredicatesDocumentation.lua:145,150` |
| `UnitPowerType` has **no** `SecretWhen*` predicate (`MayReturnNothing = true` only) | `.../UnitDocumentation.lua:2859-2868` |
| `UnitDistanceSquared(unit)` returns `(distance, checkedDistance)`, no secret predicate | `.../UnitDocumentation.lua:1108-1119` |
| `StatusBar:SetMinMaxValues` / `SetValue` accept secret arguments from tainted code and attach the `BarValue` secret aspect | `.../SimpleStatusBarAPIDocumentation.lua:229-232`, `:355-358`; `Enum.SecretAspect.BarValue = 16384` in `.../SecretAspectConstantsDocumentation.lua` |
| Blizzard's power bar passes raw `UnitPowerMax`→`SetMinMaxValues` and raw `UnitPower`→`SetValue` (no secret check) | `Interface/AddOns/Blizzard_UnitFrame/Mainline/UnitFrame.lua:939-975` (max `:948`/`:950`, value `:962`, `SetValue` `:970`) |
| `C_Spell.IsAutoRepeatSpell(spellIdentifier)` exists and is `AllowedWhenTainted` | `.../SpellDocumentation.lua:693-708` |
| Auto Shot is spell **75** on Forever | `Interface/AddOns/Blizzard_GamepadActionBars/MainActionBarFrame.lua:1-2` (`AUTO_RANGED_ATTACK_SPELL_ID = 75`), used at `:218-227` |
| `PLAYER_IN_COMBAT_CHANGED(inCombat:bool)` is a real documented event | `.../PlayerScriptDocumentation.lua:1861-1870` |
| `PLAYER_ENTER_COMBAT` / `PLAYER_LEAVE_COMBAT` exist | `.../UnitDocumentation.lua:3770`, `:3814` |
| `PLAYER_IN_COMBAT_CHANGED` on Blizzard's timer only updates presentation (`UpdateShownState`) — it does not end/clear the cycle | `.../Blizzard_SwingTimer.lua:148-149` |
| The classic library's `PLAYER_LEAVE_COMBAT` does **not** clear swing timers (it only flips `isAttacking` and first-swing flags) | `Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:757-761` (local repo) |
| Equipment slots: `INVSLOT_MAINHAND=16`, `INVSLOT_OFFHAND=17`, `INVSLOT_RANGED=18` | `Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:151-153` |

The runtime restriction state itself is not readable from the source tree. `C_Secrets`
exposes the predicates (`ShouldUnitPowerBeSecret`, `GetPowerTypeSecrecy`,
`ShouldUnitStatsBeSecret`, `HasSecretRestrictions` —
`.../SecretPredicateAPIDocumentation.lua:32-43, :93-101, :321-336, :388-396`), and
`SecrecyLevel` is `NeverSecret=0 / AlwaysSecret=1 / ContextuallySecret=2`
(`.../SecretWrapperConstantsDocumentation.lua:6-15`). §10 lists the in-client probes
that close this.

---

## 3. Symptom A — Hunter Auto Shot fires but is not displayed

### 3.1 The current pipeline, end to end

1. **Engine availability** — `swing_source.available` on Forever is
   `st.family == "FOREVER" and C_EventUtils.IsEventValid("PLAYER_SWING") == true`
   (`swing_source.lua:52-68`). `PLAYER_SWING` is documented on this branch (§2), so
   the probe is expected to pass; when it does, `_Mainline.toc` ships no
   `LibClassicSwingTimerAPI`, so `ST.swing_engine == "forever-source"`
   (`main.lua:30-43`).
2. **Event registration** — `PLAYER_SWING`, `UNIT_ATTACK_SPEED`, `WEAPON_SLOT_CHANGED`,
   `PLAYER_IN_COMBAT_CHANGED`, `PLAYER_ENTERING_WORLD` on its own hidden frame
   (`swing_source.lua:410-454`). `PLAYER_TARGET_CHANGED` and
   `PLAYER_SWING_RANGE_UPDATE` are deliberately not registered (comment
   `swing_source.lua:414-422`, verified against `Blizzard_SwingTimer.lua:142-170`).
3. **START** — `on_player_swing` maps `swingType` → `{0:"mainhand",1:"offhand",2:"ranged"}`
   (`swing_source.lua:179-200`), rejects a non-number/`<= 0` duration or an unknown
   type (`:206-217`), opens a cycle (`begin_cycle` `:149-159`), and fires
   `SWING_TIMER_START(duration, expiration, hand)` **synchronously** (`:219-223`).
   A `C_Timer.After(duration + 0.1)` fires `SWING_TIMER_STOP` only if the cycle is
   still current (counter compare, `:165-171`, `:226-228`).
4. **Dispatch** — `ST.callback_event_handler` looks up `ST[event]`; Forever payloads are
   speed-first, so the unit-id normalisation branch (leading `"player"`/`"target"`) is
   skipped and the handler is pcall-called with `(event, speed, expiration, hand)`
   (`main.lua:1251-1326`). A throwing handler is isolated, counted per event and
   announced once per event (`:1327-1339`); the per-event counter total is in the
   runtime `/st diag` line (`main.lua:3165-3172`).
5. **Bar state** — `ST:SWING_TIMER_START` writes `bar.start = now`,
   `bar.speed = speed`, `bar.ends_at = expiration` (or `now + speed` when the engine
   stamp is already past), recolours, and — only for `offhand`/`ranged` on
   `swing_engine == "forever-source"` — calls `note_hand_activity(hand, now, "forever")`
   (`main.lua:1472-1586`; the Forever receipt at `:1568-1575`).
6. **Receipt path #2 (shots)** — `UNIT_SPELLCAST_SUCCEEDED` calls
   `note_hand_activity("ranged", nil, "shot")` for ids `{75, 3018, 2764, 5019}` or their
   localized names (`main.lua:2246-2271`, `:2077-2112`, `:2261-2263`). The TBC/classic
   fallback driver is explicitly excluded on mainline clients (`:2300-2305`), so on
   Forever this path is a *receipt only*.
7. **Visibility** — driven by the 0.05 s range poll: `rf_update`
   (`main.lua:2793-2828`) → `set_bar_visibilities` (`:3113-3137`) → per hand
   `bar_is_enabled` (`:2997-3016`: `db.enabled and self[hand].has_weapon`) →
   `handle_bar_visibility` (`:3082-3111`) → configured show rule
   (`hand_show_condition_met`, `:3018-3046`; hunter ranged ships
   `show_behaviour="conditional"`, `show_condition="either"`,
   `require_in_range=false` — `config_presets.lua:657-688`, `:180-181`) → the activity
   gate for offhand/ranged (`hand_is_in_use`, `:2976-2995`; window
   `clamp(speed*2, 1.5, 8)` s, `:2925-2927`, `:2958-2974`) → `show_bar`/`hide_bar`
   (`:271-289`, `:325-377`).
8. **Fill** — the bar's own `OnUpdate`: `ST:onupdate_common` computes
   `(now - start)/(ends_at - start)`, paints `bar:SetWidth`/`SetTexCoord`, the spark,
   texts, then the class hook under `st.guard.run`, then re-asserts the fill last
   (`bars.lua:1124-1323`, fill `:1173-1178`, re-assert `:1319-1322`).
9. **Hunter overlay** — `classes/hunter.lua:1337-1396` → `hunter_ui.on_bar_update`
   (`hunter_ui.lua:1877-1896`) → `ui.update` with one guarded site per sub-feature
   (`:1824-1866`); the anchor-frame hook `ui.poll` covers frames where the bar's own
   tick cannot run (`:313-368`).

### 3.2 What can swallow exactly one shot (and recover on the next)

- **A-1 (HIGH) — payload rejection is silent for a single payload.**
  `on_player_swing` drops the cycle (no START, no bar update) when
  `hand_for_swing_type` returns nil or the duration is not a positive number
  (`swing_source.lua:206-218`). Counters go to `stats.payload_rejects` /
  `unknown_swing_type` / `malformed_duration` (`:101-112`), but the chat notice only
  fires when the reject has lasted `SUSTAINED_REJECT_SECONDS = 5` **in combat**
  (`:94-141`). One bad payload therefore looks exactly like the operator's
  "one shot consumed": the bar keeps animating the previous cycle, the next
  `PLAYER_SWING` recovers, and nothing is printed. The counters ARE surfaced:
  `swing_source:diagnostic_text()` is appended to `/st diag` (`main.lua:3236-3240`;
  `swing_source.lua:384-394`; the `/st diag` block is `main.lua:3236-3241`), and the per-hand wire counts are
  `ST.swing_wire_counts` / `swing_wire_last` (`main.lua:1428-1447`, diag reading
  `main.lua:3210-3224`).
  *Why the payload could be malformed is UNVERIFIED (§10, V1).*
- **A-2 (HIGH) — the visibility driver can die for the session.**
  `rf_update` pcalls only `self.update_range_state` (`main.lua:2803`). On success the
  pass and OOR are called **outside** the pcall (`:2825-2826`) and the re-arm is the
  *last* statement (`:2827`). Consequences:
  (a) one throw from `set_bar_visibilities`/`handle_oor` escapes the `C_Timer`
  callback and the tick chain is never re-armed — the range display and *all*
  show/hide decisions stop, with **no** `rf_disabled` and no notice;
  (b) on a failed poll the function returns before the pass (`:2804-2818`), so that
  tick shows/hides nothing; three consecutive failures call
  `disable_range_checking()` (`:2807-2810`), which sets `rf_disabled` and every later
  tick returns at `:2794-2796` — permanently, though it does print
  (`:2729-2739`).
  Either way a bar that was hidden at that moment never reappears, and a shot's
  `note_hand_activity` cannot show it because showing lives only in that poll.
- **A-3 (MED) — the activity window only tolerates missed cycles up to two, and the
  Auto-Shot backstop may be dead on Forever.** The ranged receipt lasts
  `2 × speed` s (min 1.5, max 8) (`main.lua:2958-2974`); the bar hides as `idle`
  only if two consecutive cycles deliver no receipt (`:3102-3105`). The designed
  backstop is `state.auto_repeat_active` (`:2983-2985`), written by
  `ST.HUNTER.on_autorrepeat_event` from `api.IsAutoRepeatSpell(spell_token(75))`
  (`classes/hunter.lua:1029-1062`). On Forever `spell_token` returns the localized
  **name** (`classes/hunter.lua:27-37`; `compat.lua:1950-1964`), and
  `api.IsAutoRepeatSpell` only tries the numeric fallback when the token it was
  given is a number (`compat.lua:1129-1148`) — so the id fallback is unreachable for
  a name-shaped token. Whether `C_Spell.IsAutoRepeatSpell("Auto Shot")` answers true
  on Forever is UNVERIFIED (§10, V2); `C_Spell.IsAutoRepeatSpell(75)` is the
  client's own form (`MainActionBarFrame.lua:226`).
- **A-4 (HIGH/MED trigger) — `has_weapon` can be flipped false by a restricted read
  and is not re-probed.** `check_weapons` (`main.lua:986-1012`) derives
  `ranged.has_weapon` from `api.UnitRangedDamage("player")` and `offhand.has_weapon`
  from `api.UnitAttackSpeed("player")`'s second return; compat nils any secret read
  (`compat.lua:1086-1114`), and `nil or 0` becomes 0 → `has_weapon = false`
  (`main.lua:995-1004`), and `has_oh = false` (`:1011`). The flag then gates the bar
  (`main.lua:3011`), the "why" token (`:3076`), the lazy build
  (`bars.lua:211-233`, gate at `:224-228`) and `handle_oor` (`main.lua:2835`).
  `check_weapons` runs only at init (`main.lua:941`), on the D8 late-engine rewire
  (`:510`) and on `PLAYER_EQUIPMENT_CHANGED` for slots 16/17/18 (`:1708-1725`), so a
  restricted read at one of those moments silently disables the hand until the next
  equipment change. This is the *persistent* variant of "Auto Shot not displayed".
  Note the wrapper semantics are pinned by tests (`tests/secret_guard_state.lua:973-1007`,
  including "a secret offhand read degrades the whole read to no weapon"), so the fix
  belongs in `check_weapons`, not in the wrapper.
- **A-5 (MED-LOW) — engine divergence on combat exit.** `swing_source.on_combat_changed`
  clears **every** in-flight cycle and fires `SWING_TIMER_STOP` when the player leaves
  combat (`swing_source.lua:340-354`, registered `:427/:448-449`). Neither comparator
  does this: the vendored library only flips `isAttacking`/first-swing flags
  (`Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:757-761`), and Blizzard's
  timer only re-runs presentation (`Blizzard_SwingTimer.lua:148-149`). Effect: a
  combat-state flap mid-cycle (target dies with no other aggro, vanish/feign, leash)
  ends that cycle early and fires a STOP; `main.lua` keeps the bar fields and the fill
  still completes, so this is a *shortened/mis-timed* animation rather than a missing
  one. Pinned by `tests/swing_source_state.lua:187-193` ("combat exit fires STOP"),
  which the fix lane would have to update.
- **A-6 (LOW) — isolated handler throw is one chat line.** If a `SWING_TIMER_*`
  handler throws before the bar writes, that shot's state is lost; the dispatcher
  prints once per event and counts (`main.lua:1327-1339`). A deterministic throw
  would therefore silently kill every shot after one line — the count is in the
  runtime `/st diag` line (`:3165-3172`), not on the bar line.
- **A-7 (LOW) — target flag source.** `has_attackable_target` is only written in
  `ST:UNIT_TARGET` when `unit_id == "player"` (`main.lua:2432-2445`); the addon never
  registers `PLAYER_TARGET_CHANGED` (repo-wide grep: zero registrations outside the
  vendored libs). If Forever only fires `PLAYER_TARGET_CHANGED` on a target switch,
  the "has_target"/"both" show rules read a stale flag — masked in combat by the
  default `either` rule, but it can keep a ranged bar hidden out of combat with a
  fresh attackable target. UNVERIFIED (§10, V3).

### 3.3 What does NOT swallow the shot (verified)

- **The Auto Shot red zone / hidden window / cast bar are display-only** — see §4.4.
- **The hunter class hook and the anchor hook cannot hide the swing bar.** The bar
  fill is painted before the class hook and re-asserted after it (`bars.lua:1173-1178`,
  `:1319-1322`); the class hook runs under `st.guard.run` (25-throw quarantine,
  `bars.lua:1282-1292`, `guard.lua:41` (`QUARANTINE_THROWS = 25`), `:112-130`,
  `:173-179`). A quarantined hunter site stops the *hunter visuals*, never the fill.
  The anchor hook (`hunter_ui.lua:343-368`) removes only its own OnUpdate from the
  ranged hand's anchor frame and hides only hunter widgets (`ui.hide_all`,
  `hunter_ui.lua:1783-1800`).
- **`rf_update`'s early return is not a per-tick skip on the happy path**: it returns
  before the pass only on a failed `update_range_state` (`main.lua:2804-2818`).

---

## 4. Symptom B — the horizontal range indicator stops displaying

### 4.1 The pipeline

1. `weave_range.init(self)` is called from `post_init` (`main.lua:1044-1051`), after
   the hand loop `set_gcd_marker_positions`/`on_bar_inactive` (`:1022-1027`) and the
   guarded class `post_init` (`:1029-1042`), before `lock_frames`/`show_bar`
   (`:1053-1065`) and `power_bar.init` (`:1067-1072`). `interfaces_are_initialised`
   was set true earlier (`:866`), so a throw in between is never retried.
2. `wr.init` creates the bar frame (`weave_range.lua:266-317`) and a **separate,
   never-hidden** driver frame whose OnUpdate accumulates and calls `wr.poll` at
   `wr.gate_interval` (`:304-315`, initial 0.5 s, `:306`).
3. `wr.poll` pcalls `wr.update` (`:473-497`); `wr.update` applies the enable gate
   (`:392-408`), target gates (`:410-418`), distance gate (`:420-428`), then layout +
   latched paint (`:439-466`).
4. Enable rule: `class_db.weave_range_enabled == true` → on, `== false` → off,
   `nil` → `ST.weave_range_default_enabled(class)` (`weave_range.lua:117-135`;
   reader `config_presets.lua:1679-1683`; hunter default true at `config_presets.lua:593`;
   shared default false at `:123`). Master switches `class_enabled ~= false` and
   `profile.enabled ~= false` also gate.
5. Anchor: `ST.ranged.anchor_frame.bar_frame` when it exists, else UIParent centre
   (`weave_range.lua:256-262`, `:359-365`); width follows the ranged bar
   (`:337-343`); reserved hunter widgets above (`:237-254`); screen clamp
   (`:367-381`).

### 4.2 Every way the bar can stop, with the exact gate

| # | Stop path | Exact code | Recovers? |
|---|---|---|---|
| B-1 | `wr.init` never ran (throw earlier in `post_init`, or no `CreateFrame`/`UIParent` → `wr.inert = true`) | `main.lua:1022-1051`; `weave_range.lua:266-273` | **No** — one-shot init, no retry |
| B-2 | Enable gate reads off: explicit saved `false`, `class_enabled == false`, `profile.enabled == false`, or nil+non-hunter class | `weave_range.lua:117-135`, `:403-407` | On setting change only |
| B-3 | No target (`UnitExists("target")` false) | `:410-414` | Yes, next 0.05 s tick |
| B-4 | Target not attackable (`UnitCanAttack` false) | `:415-418` | Yes |
| B-5 | Distance unknown: `st.api.UnitDistance` nil — no global, `checkedDistance == false`, non-finite/negative, throw, or secret | `:420-428`; `compat.lua:1227-1243`; client `UnitDistanceSquared` `.../UnitDocumentation.lua:1108-1119` | Yes when the client can check again |
| B-6 | Driver quarantine: 25 consecutive throws → `wr.driver:SetScript("OnUpdate", nil)` + hide | `weave_range.lua:469-497` (`QUARANTINE_ROWS = 25`, `:471`) | **No** — session-long |
| B-7 | Layout: anchor nil → centred on UIParent (still shows); width/height changes; clamp only every 1 s | `:333-382` | n/a (not a hide path) |
| B-8 | Frame is `MEDIUM` strata, mouse-disabled; can be covered by a higher-strata frame | `:275-300` (`SetFrameStrata("MEDIUM")` `:279`) | Visual only |

Notes:

- **B-5 is the most probable "worked at first, then stopped" shape.** On Forever the
  global exists and is not secret-gated, but the second return is the client's
  "was this distance actually checked" answer; Blizzard's own consumer only trusts the
  reading when it is true (`origin/forever:Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua:1068-1078`).
  When the target leaves the client's checkable state, compat returns nil and the bar
  hides **by documented contract** (`weave_range.lua:16-17`, `:424-428`). Changing that
  is an operator decision (see §7.6), not a silent fix.
- **B-6 is a real trap.** 25 throws at 0.05 s is ~1.25 s of a repeating error; the
  module then removes its own OnUpdate and hides, with one chat line (first failure)
  and no `/st diag` receipt. `wr.last_error`/`wr.failures` are stored but not rendered
  anywhere (grep: only `weave_range.lua` writes them).
- **B-1 is the second real trap.** Because the power bar is initialised after
  `weave_range.init` in the same unguarded tail, one throw can take out *both* bars
  (see C-3).
- **There is no `/st diag` line for this bar.** `diag.lua` has a power-bar line
  (`diag.lua:795-932`) and hand lines, but nothing reads `st.weave_range`; "worked
  then stopped" is unattributable in-client today.

---

## 5. Symptom C — the power bar does not show on Forever

### 5.1 The pipeline

1. `post_init` calls `st.power_bar.init(self)` after the swing bars are built and shown
   (`main.lua:1063-1072`). `init` creates a **plain Frame** with a background texture,
   a `fill` **texture** and a FontString, plus a 0.25 s driver and an event frame
   (`power_bar.lua:525-581`; frame `:533-559`, driver `:561-572`, events `:489-521`).
2. `pb.update` resolves (`pb.resolve`, `:382-433`) then lays out and paints
   (`:437-453`): fraction from `value/max` (`:89-102`), fill width from the fraction
   (`:333-374`), label from `math.floor` (`:115-124`).
3. `pb.resolve` gates, in order: `no-frame` (`:384-387`) → `no-addon` (`:388-391`) →
   `off` (enable rule `:128-139`) → `no-anchor` (`:399-403`; needs a **visible** melee
   row, `:204-240`) → `no-api` (`:406-411`) → `no-type`
   (`api.UnitPowerType("player")`, `:412-416`) → `no-value`
   (`type(value) ~= "number" or type(max) ~= "number" or max <= 0`, `:418-423`) →
   `no-fraction` (`:426-430`).
4. Reads go through compat: `api.UnitPowerType` (`compat.lua:626-649`),
   `api.UnitPower` (`:599-611`), `api.UnitPowerMax` (`:612-624`). Each wrapper returns
   **nil** when the client value is secret (`is_secret` = `issecretvalue`,
   `compat.lua:163-176`; the regime note at `:163-171` states type() still reports the
   underlying type and arithmetic/comparison/index raise).

### 5.2 The concrete block (C-1, HIGH)

- `UnitPower` is `SecretWhenUnitPowerRestricted` and `UnitPowerMax` is
  `SecretWhenUnitPowerMaxRestricted` (`.../UnitDocumentation.lua:2732-2739`,
  `:2801-2808`; predicates `.../SecretPredicatesDocumentation.lua:145,150`).
  The operator's in-client reading is that the power read *is* restricted on Forever;
  that matches the predicate set (`SecretWhenUnitPowerRestricted` applies per power
  type unless the type is flagged `NeverSecret` — `.../SecretPredicatesDocumentation.lua:150-153`).
- Current code: compat nils the secret → `pb.resolve` returns `no-value` → `pb.update`
  hides (`power_bar.lua:444-447`). `/st diag`'s power line reads the same wrappers and
  would print `value=unknown why=no-value` (`diag.lua:818-871`, `:873-932`).
- Even if compat returned the raw secret, the current paint **cannot** consume it:
  `pb.fraction` compares (`:89-102`), `pb.format_value` does `math.floor` (`:115-124`),
  `pb.resolve` compares `max_value <= 0` (`:420`), and the fill is a texture width
  (`:344-351`). Per compat's own note (`compat.lua:163-171`), arithmetic/comparison on
  a secret raises.

### 5.3 The supported pass-through path (verified on origin/forever)

- `StatusBar:SetMinMaxValues(minValue, maxValue)`:
  `SecretArguments = "AllowedWhenTainted"`, `SecretArgumentsAddAspect = { Enum.SecretAspect.BarValue }`
  — `origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua:229-232`.
- `StatusBar:SetValue(value)` — same markers — `.../SimpleStatusBarAPIDocumentation.lua:355-358`.
- `Enum.SecretAspect.BarValue = 16384` — `.../SecretAspectConstantsDocumentation.lua` (SecretAspect table).
- Blizzard's own power bar does exactly this, from the (tainted) unit-frame addon, with
  **no** secret check: `local maxValue = UnitPowerMax(unit, statusbar.powerType)` →
  `statusbar:SetMinMaxValues(0, maxValue)` (`Blizzard_UnitFrame/Mainline/UnitFrame.lua:948`,
  `:950`), `local currValue = UnitPower(unit, statusbar.powerType)` → `SetValue(currValue)`
  (`:962`, `:970`). The same file's health bar does the same with `UnitHealthMax`
  (`:703-704`).
- So **the secret data can be passed through a StatusBar from tainted addon Lua** — the
  draft's "passthrough is not supported by evidence" claim was wrong (see §11).

### 5.4 The other gates (C-2…C-5)

- **C-2 (MED) `no-anchor`.** `choose_anchor` requires at least one melee bar to be
  *visible* (`power_bar.lua:204-240`); the mainhand bar is conditional by default
  (`show_behaviour="conditional"`, `show_condition="either"` — `config_presets.lua:180-181`),
  so out of combat with no attackable target the power bar is absent even with a
  readable power value. This is stated design (`power_bar.lua:16-27`), but it is a
  second, independent hide reason that looks identical to C-1 without `why=`
  (`diag.lua:807-816`).
- **C-3 (MED) init order.** `power_bar.init` is the last widget init in `post_init`
  (`main.lua:1067-1072`), after the unguarded hand loop (`:1022-1027`) and
  `weave_range.init` (`:1049-1051`). A throw in any earlier step leaves
  `pb.frame == nil` → `why=no-frame` for the session (`power_bar.lua:384-387`);
  `interfaces_are_initialised` is already true (`main.lua:866`), so nothing retries.
- **C-4 (INFO) ruled out.** `no-type` is not expected on Forever: `UnitPowerType` has no
  `SecretWhen*` predicate (`.../UnitDocumentation.lua:2859-2868`); `no-api` cannot
  happen (compat always defines all three functions, `compat.lua:599-649`); the
  0.25 s driver runs even if every power event were rejected by
  `C_EventUtils.IsEventValid` (`power_bar.lua:561-572`, `:498-521`).
- **C-5 (LOW) naive-fix hazard.** Removing the nil without a paint path makes
  `max_value <= 0` (`:420`) and `pb.fraction` (`:92-100`) throw on a secret; the
  pass-through must be wired end to end.

---

## 6. Ranked findings

Severity: HIGH = a shipped user-visible failure with no recovery; MED = a real gate or
robustness defect whose trigger is narrower; LOW = observability/edge.
Confidence is about the *code claim*; trigger confidence is stated separately.

| ID | Sev | Conf | Finding | Exact code |
|---|---|---|---|---|
| C-1 | HIGH | HIGH | Power bar structurally cannot render a restricted power read: compat nils it and the module paints with arithmetic on a texture. The documented+Blizzard-used pass-through (StatusBar) is not implemented. | `compat.lua:599-624`, `power_bar.lua:89-124`, `:333-374`, `:418-423` |
| A-1 | HIGH | MED | A single rejected `PLAYER_SWING` payload silently drops one shot's display; notice only after 5 s in combat; counters only in `/st diag`. | `swing_source.lua:94-141`, `:206-229`, `:384-394`; `main.lua:3236-3240` |
| A-2 | HIGH | HIGH (defect) / UNVERIFIED (trigger) | Visibility driver can stop for the session: pass and OOR are outside the pcall and the re-arm is last; 3 poll failures disable range checking permanently. | `main.lua:2793-2828`, `:2729-2739` |
| B-1 | HIGH | HIGH (defect) / UNVERIFIED (trigger) | Range bar never initialised if `post_init` aborts before `weave_range.init`; no retry. | `main.lua:1014-1051`; `weave_range.lua:266-273` |
| B-6 | HIGH | HIGH (defect) | Driver self-quarantine removes its own OnUpdate after 25 throws; permanent for the session; no `/st diag` receipt. | `weave_range.lua:469-497` |
| A-3 | HIGH | HIGH (code) / MED (trigger) | `has_weapon` derived from secret-capable stat reads; nil read as "no weapon"; re-probed only on equipment change; disables build + enabled + OOR. | `main.lua:986-1012`, `:3011`, `:3076`; `bars.lua:224-228`; `compat.lua:1086-1114` |
| B-5 | MED | HIGH (code) / UNVERIFIED (how often) | `UnitDistance` nil (client `checkedDistance == false`) hides the bar by contract; no fallback and no receipt. | `weave_range.lua:420-428`; `compat.lua:1227-1243` |
| A-4 | MED | MED | Auto-repeat backstop may be dead on Forever: `api.IsAutoRepeatSpell` is called with a localized name and only falls back to an id when the token is numeric. | `compat.lua:1129-1148`; `classes/hunter.lua:27-37`, `:1029-1062` |
| C-2 | MED | HIGH | Power bar needs a *visible* melee row; conditional MH show rule hides it out of combat with no attackable target. | `power_bar.lua:204-240`; `config_presets.lua:180-181` |
| C-3 | MED | HIGH (defect) / UNVERIFIED (trigger) | Power bar init is last in an unguarded `post_init` tail; `no-frame` for the session if anything earlier throws. | `main.lua:1022-1072`; `power_bar.lua:384-387` |
| A-5 | MED-LOW | MED | Forever engine clears every cycle on combat exit; both comparators keep the cycle. Visible as a shortened/mis-timed animation, not a missing shot. | `swing_source.lua:340-354`; lib `:757-761`; `Blizzard_SwingTimer.lua:148-149` |
| A-6 | LOW | HIGH | A throwing `SWING_TIMER_*` handler loses that shot's state; one chat line per event, count only in the runtime line. | `main.lua:1327-1339`, `:3165-3172` |
| A-7 | LOW | UNVERIFIED | `has_attackable_target` only updates on `UNIT_TARGET("player")`; `PLAYER_TARGET_CHANGED` is never registered by the addon. | `main.lua:2432-2445` |
| B-2 | LOW | HIGH | Enable gate priority: an explicit saved `false` on a hunter profile beats the new default; master switches also gate. Not a bug — first check. | `weave_range.lua:117-135`; `config_presets.lua:593`, `:1679-1683` |
| B-7 | LOW | HIGH | No `/st diag` line for the range bar; `wr.last_error`/`wr.failures` are written but never rendered. | `weave_range.lua:480-485`; `diag.lua` (no reader) |

---

## 7. Minimal fix proposals (no code was changed by this desk)

### 7.1 C-1 — power bar pass-through (highest value, smallest blast radius)

1. **compat (new, non-breaking):** add a restricted-aware read used only by
   `power_bar.lua`, e.g. `api.UnitPowerState(unit, power_type)` returning
   `(value, restricted)` where `restricted = is_secret(raw)` and `value` is the **raw**
   value (or nil when the wrapper itself cannot answer). Keep `api.UnitPower` /
   `api.UnitPowerMax` exactly as they are: `tests/secret_guard_state.lua:661-690` pins
   the nil-for-secret contract, and other consumers (warrior rage, hunter `mana_frac`,
   guide gather) must keep it.
2. **power_bar frame:** create `pb.frame` as a real StatusBar
   (`CreateFrame("StatusBar", addon_name .. "PowerBar", UIParent)`), set a
   statusbar texture from the class colour, keep the background texture and the
   FontString. Remove the width-driven `frame.fill` texture path (`power_bar.lua:538-545`,
   `:339-351`).
3. **paint:** when `restricted` is true, call
   `frame:SetMinMaxValues(0, max_value)` and `frame:SetValue(value)` with the **raw**
   values (the documented, Blizzard-used pattern — §5.3), hide the text, and show the
   frame. When not restricted, keep today's exact visuals plus the same
   `SetMinMaxValues`/`SetValue` (or `SetValue` only; the fill then needs no arithmetic).
4. **resolve/update:** return `state.restricted = true` with value/max **before** the
   `type()/max <= 0` comparisons (`power_bar.lua:418-423`) and before `pb.fraction`;
   `pb.update` must not compute a fraction for a restricted read.
5. **diag:** add `restricted` next to `no-value` in `diag.lua:807-816` and print
   `value=restricted` instead of `unknown` when the flag is set, so the state is
   distinguishable from a real unknown.
6. **tests:** add restricted cases in `tests/power_bar_state.lua` (stub StatusBar +
   raw secret sentinel), keep `tests/secret_guard_state.lua` untouched, and prove the
   existing 190 power-bar checks stay green.

### 7.2 A-1 — make a dropped shot observable, not silent

- Lower the sustained-reject notice for a *ranged* reject: print once when
  `stats.malformed_duration + stats.unknown_swing_type` increments **and** the hand is
  `ranged` (or include the counters in the per-hand `/st diag` bar line, not only the
  swing-source line). Keep the 5 s combat rule for the general "feed is broken"
  message.
- Keep the existing counters; no behaviour change to the timing.
- No client fix is proposed here until V1 in §10 says what the malformed payload is.

### 7.3 A-2 — never leave the visibility poll unarmed

```lua
-- main.lua rf_update: one guarded body, one unconditional re-arm
local function tick()
  local ok, err = pcall(self.update_range_state, self)
  ... -- existing failure accounting (or fold in)
  if ok then
    self:arm_ranged_shot_reset_guard_tick()
    self:set_bar_visibilities()
    self:handle_oor()
  end
end
local ok, err = pcall(tick)
if not ok then ...count/announce once... end
C_Timer.After(self.rangefinder_interval, self.rf_tick_fn)   -- always
```

Keep `rf_disabled` as the *hard* off switch only (the notice already exists); a
non-fatal throw must stay recoverable and must never end the chain.

### 7.4 A-3 — `has_weapon` must mean "no weapon", never "unknown"

In `check_weapons` (`main.lua:986-1012`), update only on a **readable** answer:

```lua
local oh = select(2, api.UnitAttackSpeed("player"))
if type(oh) == "number" then self.offhand.has_weapon = oh > 0 end
local ranged = api.UnitRangedDamage("player")
if type(ranged) == "number" then self.ranged.has_weapon = ranged > 0 end
self.has_oh = self.offhand.has_weapon
```

A nil (restricted / absent global) leaves the previous value, so a mid-session swap
under restriction cannot disable the bar. (A genuine unequip still answers 0 on a
readable client, clearing the flag; a restricted unequip clears on the next readable
probe — the activity gate hides the bar in the meantime.) If the fix lane needs to
distinguish them in `/st diag`, add a `weapon_probe=readable|restricted|absent` token.
Do **not** change the compat wrappers (pinned).

### 7.5 A-4 — auto-repeat probe form

Call `api.IsAutoRepeatSpell(AUTO_SHOT_ID)` (numeric 75 — the client's own form,
`MainActionBarFrame.lua:226`) instead of the name-shaped `spell_token(75)` in
`classes/hunter.lua:1046`, or extend `compat.api.IsAutoRepeatSpell` to try
`probe(spell)` then `probe(<numeric>)` when the first answer is false. This is safe on
every family (`C_Spell.IsAutoRepeatSpell` takes a `SpellIdentifier`; the classic global
takes an id).

### 7.6 A-5 / B-5 — contract decisions (ask the operator before changing)

- **A-5:** stop clearing cycles on combat exit in `swing_source.on_combat_changed` and
  let the scheduled stops end them (mirrors both comparators). Needs
  `tests/swing_source_state.lua:187-193` updated by the owning lane.
- **B-5:** keep "unknown hides" or render an explicit unknown face. Recommend: add
  the `why` receipt first (§7.7), and only change the contract on an operator ruling.

### 7.7 B — make the range bar attributable and recoverable

1. Store `wr.last_state = { why = "off"|"no-target"|"no-attackable"|"no-distance",
   yards = n }` in `wr.update` at each early return (same pattern as
   `power_bar.lua:382-433`), and render one `/st diag` line from it.
2. Make the quarantine recoverable: keep the driver armed, skip the body for a backoff
   (e.g. 30 s) with the failure counter reset only on success, and print the count.
3. Guard the `weave_range.init`/`power_bar.init` call sites in `post_init` (pcall +
   one notice) and add a one-shot retry from `PLAYER_ENTERING_WORLD` if either module
   has no frame yet.

---

## 8. The Auto-Shot red-zone contract (operator ruling) — verdict

Ruling: *the red zone is a display-only indicator; its absence must never hide, gate,
quarantine or short-circuit the swing bar, the ranged START/UPDATE state, the shot
receipt, or the hunter visual set; it draws only when a live ranged cycle exists.*

Current tree, verified read-only:

| Check | Evidence | Verdict |
|---|---|---|
| Zone updater writes no bar state | `hunter_ui.lua:1046-1111` touches only `ui.cast_zone`, `ui.cast_zone_marker`, `ui.zone_safe/zone_width/zone_left/zone_colored` | PASS |
| Zone draws only with a live ranged cycle | `hunter_ui.lua:1060-1073` (`ranged.start` + `synced_duration or speed`, `now <= start + duration`) | PASS (matches the ruling) |
| Cast bar / hidden window write no bar state | `hunter_ui.lua:904-1035`; the window cache `ranged.hidden_window_start/duration` (`:827-865`) is read only by `gather_guide_inputs` (`classes/hunter.lua:3187-3234`) — no visibility reader consults it (`main.lua:2925-3137`) | PASS |
| No hunter module hides/shows the swing bar | repo grep: `hide_bar(` only in `main.lua:271-289` callers; no `show_bar(`/`hide_bar(` in `hunter_ui.lua` | PASS |
| Zone/window cannot gate the receipt | the receipt is written in `main.lua:1568-1575`/`:2261-2263`, before/independent of any hunter UI code | PASS |
| Tick-host failure is contained | `ui.poll` removes only its own OnUpdate from the anchor frame and hides hunter widgets (`hunter_ui.lua:343-368`, `1783-1800`); the swing bar's own OnUpdate is on the bar frame (`bars.lua:1325-1335`) | PASS |

One coupling exists but points the correct way: the **whole hunter visual set** is
gated by `ranged_bar_ready`/`ranged_ui_allowed` (`hunter_ui.lua:1829-1849`), i.e. the
bar gates the set, never the reverse. No code in the tree violates the ruling; the
ruling should be pinned by a test in the display-fix lane so a future edit cannot
introduce the coupling.

---

## 9. Observations outside the three symptoms (for the fix lanes)

- `A-2`'s unprotected tail also means a throw in `set_bar_visibilities` kills the
  **out-of-range alpha** and the **offhand** show/hide, not only the ranged bar.
- `bars.lua`'s class hook site is per class (`class:<CLASS>:on_bar_update`,
  `bars.lua:1282-1292`), so hunter quarantine cannot affect the paladin/other classes.
- `swing_source` registers `UNIT_ATTACK_SPEED` (unit event, `swing_source.lua:433-437`)
  but not `UNIT_INVENTORY_CHANGED`, which Blizzard registers as an enter-world
  workaround (`Blizzard_SwingTimer.lua:157-163`). Harmless for display (each
  `PLAYER_SWING` carries its duration) but worth knowing when debugging a swap.
- `weave_range` anchors above the ranged bar and reserves the hunter cast-bar/Rapid
  Fire heights (`weave_range.lua:237-254`); with the melee stack ON
  (`config_presets.lua:564`) the bar sits above the whole hunter stack — correct, and
  not a hide path.

---

## 10. UNVERIFIED items and the evidence that closes them

| # | Unverified | Why it matters | What closes it |
|---|---|---|---|
| V1 | What the client sends for the dropped ranged cycle (nil/0 duration, unknown swing type, or no `PLAYER_SWING` at all) | Decides whether A-1 is a reject or a missing event | In-client `/st diag`: `swing source payload_rejects=… unknown_type=… malformed_duration=… valid_swings=…` plus `swing_ranged=start/update/stop` and `swing_last=` (main.lua:3210-3240). One fight with a missed shot identifies the counter that moved. |
| V2 | `C_Spell.IsAutoRepeatSpell("Auto Shot")` vs `(75)` on Forever | If the name form answers false, the ranged activity backstop is dead | `/run print(C_Spell.IsAutoRepeatSpell("Auto Shot"), C_Spell.IsAutoRepeatSpell(75))` in a Forever session, with Auto Shot toggled on. |
| V3 | Whether Forever fires `UNIT_TARGET("player")` on a target switch (the addon registers no `PLAYER_TARGET_CHANGED`) | `has_attackable_target` staleness for the target-based show rules | `/run print(IsEventValid)`-style check or a `/st diag` observation of the hand line's `why=` when switching targets out of combat. |
| V4 | `C_Secrets.ShouldUnitPowerBeSecret("player", type)` / `GetPowerTypeSecrecy(type)` / `ShouldUnitStatsBeSecret()` at the moment the bar hides | Confirms the *trigger* for C-1 and A-3 (the operator's report says restricted; the doc says contextual) | `/run print(C_Secrets.HasSecretRestrictions(), C_Secrets.GetPowerTypeSecrecy(UnitPowerType("player")))` — then repeat in combat with a target. |
| V5 | Whether `UNIT_SPELLCAST_SUCCEEDED(75)` fires per Auto Shot on Forever | The "shot" receipt path would be a second, independent receipt | `/st diag` `src=` on the ranged hand line (`diag.lua:634-648`): `forever` vs `shot`. |
| V6 | Whether PLAYER_SWING ranged is delivered for *every* cycle (no client coalescing) | Distinguishes A-1 from "event missing" | Same as V1; plus a WeakAura/log comparison of the client's own swing timer. |
| V7 | Whether hidden frames run OnUpdate (used by the HU-37 design) | The anchor-hook design assumes they do not | Already flagged in `bench/publish_audit_2026-10-28.md` §G step 5; standard client semantics, not observed by this desk. |

The in-client probes above are `/run` lines; they touch no addon code. No other gap was
papered over: where the tree could not answer, this report says so.

---

## 11. Corrections to the earlier draft (`bench/swedge_addon_audit_forever_display_2026-11-06.md`)

1. **Wrong:** "API evidence supports current nil degradation. Secret values cannot be
   used in Lua arithmetic/comparisons, so passthrough is not supported by evidence or
   tests." **Correct:** passthrough *is* the client-supported path. `StatusBar:SetMinMaxValues`
   (`SimpleStatusBarAPIDocumentation.lua:229-232`) and `SetValue` (`:355-358`) are
   `SecretArguments = "AllowedWhenTainted"` with `SecretArgumentsAddAspect = { BarValue }`,
   and Blizzard's own power bar passes raw `UnitPowerMax`/`UnitPower` into them from
   tainted addon Lua (`Blizzard_UnitFrame/Mainline/UnitFrame.lua:939-975`). The addon
   hides because compat nils the read and `power_bar` paints a texture with arithmetic —
   not because passthrough is unsupported. Fix design in §7.1.
2. **Wrong:** "If a next minor release is approved, target 2.2.0." **Removed.** This
   report makes no version-target claim; the version/docs desk owns the fields. At read
   time the working tree read `2.2.0` (uncommitted) while the `release-version` desk
   journal records the operator-approved `2.1.8` — re-check before publishing.
3. The draft's "driver availability is not the likely cause" for the range bar is
   incomplete: driver availability *is* a stop path (B-1/B-6), and the driver can be
   dead without any chat line (§4.2).
4. The draft's Auto Shot section omits the payload-reject path (A-1), the visibility
   driver's unprotected tail (A-2) and the `has_weapon` flip (A-3), which are the
   concrete swallow/gate paths in the code.

---

## 12. Read-only attestation

- Product files, tests, TOCs, README/CHANGELOG, `Libs/`, `docs/` and git history were
  **not** modified by this desk.
- Only new files: this report, `desks/forever-audit/journal.md`,
  `desks/forever-audit/.signals/<ts>.json`.
- No git command that writes was run. Line endings in every read file were left as
  found.
- All Forever claims in this report were checked against `origin/forever` at
  `eac30af59 1.60.1 (70790)`; the checked-out reference branch is `classic_era`, so the
  branch was named explicitly on every read.
