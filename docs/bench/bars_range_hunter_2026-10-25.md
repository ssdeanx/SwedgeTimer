# bars-range-hunter — hunter mainhand vs ranged, and the standalone ranged-distance bar

Desk `bars-range-hunter`, lane session `ses_e8c1621f9ffe2EsMz0luIPLGi1`, 2026-10-25.
Operator intent (verbatim, 2026-10-25): "fix how main hand bar works for hunter. It looks
like it is mixed up with ranged bar" and "the ranged distance should be its own bar ...
fills up when i get closer to melee range ... it is for melee weaving".

Write scope held: `hunter_ui.lua`, `classes/hunter.lua`, `weave_range.lua`,
`tests/hunter_state.lua`, `tests/weave_range_state.lua`, new `tests/weave_bar_state.lua`,
`tests/bars_state.lua` (one real contract pin only — stated in §7). No git, no
lint-config, no TOC/main/compat/config/options/practice/nextaction/hud/Libs edits.

**Verdict.** Two independent defects made the hunter mainhand bar look welded to the
ranged bar, and both are fixed:

1. **Engine:** the vendored swing library restarts BOTH melee hands on every completed
   tracked cast, and Auto Shot is a cast on the classic line. Proven on the SHIPPED
   library, not a fixture (§4.1). Fixed our-side with a class guard that arms the
   engine's own `preventSwingReset` while an Auto Shot cast is live at range (§4.3).
2. **Layout:** `hunter_ui` re-anchored the mainhand/offhand bars under the ranged bar
   whenever the hunter cast bar was visible — and the cast bar is visible for the Auto
   Shot hidden-window face in 0.5 s of EVERY ranged cycle, so the melee bars hopped into
   the ranged stack at range with no melee activity at all. The re-anchor is retired
   (§3).

The ranged-distance bar is rebuilt as a standalone horizontal fill bar (`weave_range.lua`)
with `st.api.UnitDistance("target")` as its only distance source (HU-23), ON by default
for hunters, and hidden with no distance read on every disabled/unknown path (§5).

---

## 1. Files changed

| File | Change |
|---|---|
| `hunter_ui.lua` | melee re-anchor retired (helper + 3 call sites + `LWIN`/`get_anchor` removed); header/notes rewritten. |
| `classes/hunter.lua` | new Auto Shot cast guard (`suppress_auto_shot_melee_reset`, +3 file-scope locals), called from `on_bar_update` before the hand gate. |
| `weave_range.lua` | rewritten as the standalone horizontal distance bar (pure helpers + frame driver + guarded poll). |
| `tests/weave_range_state.lua` | rewritten: the pure maths + the enable rule + the source contract. |
| `tests/weave_bar_state.lua` | NEW (96 checks): frame creation, anchoring, screen clamp, gate order, paint maths, paint latching, cadence, guard. |
| `tests/hunter_state.lua` | 14d re-cut to the retired-anchor contract; new §14l (guard contract) and §14m (REAL-engine proof). |
| `tests/bars_state.lua` | one pin re-cut (bars_state.lua:2168-2186): a visible cast bar must move no melee bar. **The only bars_state edit, and it exists because the presentation contract changed.** |

Local-count gate (`tests/toc_check.lua`'s compiler count, limit 190):
`classes/hunter.lua` **179** (was 176 by the same measure; +3 file-scope locals: the two
matchers and the melee probe — all three are real helpers, none avoidable as module-table
lookups). `hunter_ui.lua` 64, `weave_range.lua` 18, `bars.lua` 42.

---

## 2. Task A — per-hand truth table (every writer, every read, every frame)

### 2.1 Which event writes which hand

| Hand | Writer | Speed source | Frame painted | Own-cycle only? |
|---|---|---|---|---|
| `mainhand` | lib CLEU `SWING_DAMAGE`/`SWING_MISSED` with `isOffHand=false` (`LibClassicSwingTimerAPI.lua:398-414`) → `SwingStart("mainhand")` (`:120-137`) → `SWING_TIMER_START` → `main.lua:1356 ST:SWING_TIMER_START`; `SWING_TIMER_UPDATE` → `main.lua:1513`; STOP → `main.lua:1458` | `UnitAttackSpeed("player")` first return (`lib:129`, `main.lua:1944`) | `ST.mainhand` → `bars.lua:747 onupdate_common("mainhand")` → `get_visuals_frame("mainhand")` | ✅ |
| `offhand` | same CLEU with `isOffHand=true` (`lib:406-408`); `SwingStart("offhand")` (`lib:138-169`) | `UnitAttackSpeed("player")` second return (`lib:146`) | `ST.offhand` → `onupdate_common("offhand")` (`bars.lua:931`) | ✅ |
| `ranged` | lib `ranged_swing[spell]` on `SUCCEEDED` (`lib:606-612`) and Era `SPELL_CAST_START` (`lib:458-468`); `SwingStart("ranged")` (`lib:170-189`); app fallback `maybe_drive_ranged_fallback` (`main.lua:2032-2115`) drives `callback_event_handler("SWING_TIMER_START", speed, now+speed, "ranged")` (`main.lua:2106`) | `UnitRangedDamage("player")` (`lib:177`, `main.lua:1942`, `:2084`) | `ST.ranged` → `onupdate_common("ranged")` (`bars.lua:935`) | ✅ |

Verified negatives (grepped, not assumed): no ranged event writes `self.mainhand` or
`self.offhand`; no melee event writes `self.ranged` **on the classic line**. The one
cross-write is the lib's Wrath/Cata-only re-arm of `ranged` on a melee hit
(`lib:409-417`), which is that client's intended behaviour and does not exist on
Era/TBC/Titanforge. `restart_swing_for_reset` (`main.lua:1935-1969`) writes each hand
with its own speed source and is reached only from the paladin reset spells (HoJ/Holy
Wrath, `main.lua:1971-1991`), so it is inert for a hunter.

`bars.lua` per-hand reads/writes are all keyed by the `hand` argument:
`onupdate_common` (`:747`), `set_bar_texts` (`:1197`), `set_bar_color` (`:1327`,
class hook `:1346-1350`), `on_bar_active/inactive` (`:968`, `:994`). No shared state, no
cross-hand write.

Cross-hand isolation is already pinned over the REAL stack (real lib + real v7 + real
main.lua): `tests/real_wire_state.lua:1499-1535` asserts "a START on one hand never moves
the other two hands' anchors" — run this session, 978 checks / 0 failures (2
expected-fail pending HU-29). Nothing in this wave loosens it.

`classes/hunter.lua` ranged sync writes `self.ranged` only: `on_cooldown_update`
(`:853-889`, `synced_duration` + the 0.01 s drift re-anchor), `on_autorrepeat_event`
(`:891-924`, `auto_repeat_active` + the deduped logical anchor), the Feign Death clear in
`on_spellcast_succeeded` (`:998-1017`). `set_bar_color` (`:1272-1303`) returns early for
every hand except `mainhand`.

**So the "mixing" was never state ownership.** It was (a) the engine resetting the melee
hands on a ranged cast and (b) the ranged UI moving the melee frames.

### 2.2 What the frame actually paints

`onupdate_common(hand)` paints `frame.bar` width from `d.start/speed/ends_at` of THAT
hand (`bars.lua:780-801`); `set_bar_texts` prints `d.speed` / `ends_at - now`
(`bars.lua:1219-1228`). Both are hand-local. There is no path by which the ranged cycle
can be painted on the mainhand bar except by writing `ST.mainhand.start/speed/ends_at` —
which only the melee events above do.

---

## 3. Root cause 1 (layout): the melee re-anchor fired on the Auto Shot window face

Pre-fix `hunter_ui.lua:508-546` (`git HEAD`): `ui.sync_melee_anchor` re-anchored the
mainhand and offhand anchor frames under the ranged bar while
`frame_visible(ui.cast_frame)` was true (`:514`), and handed them back to LibWindow when
it went false. **The cast bar is visible for the Auto Shot hidden-window face**: in
`ui.update_cast_bar`, `cast_bar_display` returns `"window"` for the last 0.5 s of the
ranged cycle (`hunter_window.lua:179-189`) and that path shows the cast frame
(`hunter_ui.lua:631-731`). So at range, with no melee swing, the mainhand and offhand
bars hopped into the ranged stack once per Auto Shot and back — exactly the operator's
"mixed up with the ranged bar".

Why the reference can stack them and we cannot: SuperSwingTimer hides the hunter MH bar
whenever the ranged cycle OR the cast bar is up (`SuperSwingTimer_UI.lua:2650-2670`:
`showMH = ... hunterMeleeVisible and not (effectiveRangedActive or hunterCastVisible)`),
so its stack never produces visible movement. This addon deliberately keeps the melee
cycle visible at range — that is the melee-weave workflow — so the stack has no place to
live.

**Fix:** the mechanism, its helper `anchor_hand_top_below`, `MELEE_ANCHOR_GAP`, the
`LWIN` fetch and `get_anchor` are removed (`hunter_ui.lua:472-488` documents the
retirement). `ui.on_bar_update` now drives the visual set from the ranged tick only and
moves no other hand's frame (`hunter_ui.lua:1561-1576`). Each bar keeps its own LibWindow
position.

---

## 4. Root cause 2 (engine): a completed cast restarts BOTH melee hands, and Auto Shot is a cast

### 4.1 The defect, proven on the SHIPPED library (not a fixture — lesson 11)

`Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:596-604`:

```lua
if (spell and reset_swing_spells and reset_swing_spells[spell]) or (unit.casting and not unit.preventSwingReset) then
    ... unit:SwingStart("mainhand", now, true); unit:SwingStart("offhand", now, true)
```

A scripted harness loaded the real `Libs/LibStub`, the real `CallbackHandler-1.0` and the
real vendored library (BCC tables: `WOW_PROJECT_ID=5`, `LE_EXPANSION_LEVEL_CURRENT=1`,
offhand 1.7 s) and recorded every `SWING_TIMER_*` the library fires. Output, verbatim from
the FIRST pass (before the lib lane's same-day hunter-shot exemptions landed; **§4.4 is the
current-tree table across all three branches**, and the Auto Shot half is unchanged):

```
== TBC Anniversary
Auto Shot 75 START+SUCCEEDED:
    SWING_TIMER_START hand=mainhand (player, 2.6, 1002.6, mainhand)
    SWING_TIMER_START hand=offhand  (player, 1.7, 1001.7, offhand)
    SWING_TIMER_START hand=ranged   (player, 3,   1003,   ranged)
Steady Shot 34120 START+SUCCEEDED: (no swing events)
Aimed Shot 19434 START+SUCCEEDED:
    SWING_TIMER_START hand=mainhand (...)
    SWING_TIMER_START hand=offhand  (...)
player SWING_DAMAGE (isOffHand=false): STOP:mainhand + START:mainhand
player SWING_DAMAGE (isOffHand=true):  STOP:offhand  + START:offhand
player RANGE_DAMAGE:                   (no swing events)
library-internal SwingStart('ranged'): STOP:ranged + START:ranged
```

Two facts fall out:

- **Auto Shot (75) restarts the mainhand AND offhand cycles, at ranged speed 3.0 but
  melee speed 2.6/1.7** — the mainhand bar sweeps a full melee cycle every Auto Shot.
- Ranged traffic by itself is clean: a `ranged` switch writes only `ranged`, and the CLEU
  melee branches write only the hand they belong to. The contamination is exclusively the
  cast-completion branch.

### 4.2 Correction to the wave's inherited lead

The orchestrator's pre-reconcile note said "Steady 34120 / Multi 2643 / Aimed 19434 are
not [exempt] — so each shot can re-anchor the melee bars". **Steady Shot was already
exempt** in the BCC table (`[34120]`, `[25258]`) and fires nothing (proven above). The
real cast-time leak was Auto Shot (75) and Aimed Shot (19434). (Multi-Shot/Arcane/Serpent
are instants, so they never set `casting`.) The cross-client-engine lane has since
exempted the hunter ranged damage shots in the vendored tables (Auto Shot deliberately
left out — see §4.3), which closes the Aimed half; the Auto Shot half is range-dependent
and stays ours.

### 4.3 Our-side fix: the class guard (range-dependent, reference rule)

`classes/hunter.lua:822-851` (`ST.HUNTER.suppress_auto_shot_melee_reset`), called from
`on_bar_update` before the hand gate (`classes/hunter.lua:1151-1156`).

- Reads the engine's own unit table (`LibStub("LibClassicSwingTimerAPI", true)` →
  `lib:getUnit("player")`, cached on `ST.HUNTER.swing_unit_cache`; nil before
  ADDON_LOADED, retried next tick).
- Only acts while `unit.casting == true` and the tracked cast is Auto Shot (id 75, or the
  client's own localized name) — i.e. exactly the window in which the reset branch can
  fire.
- **In melee it does nothing**, because the shot really does delay a melee swing there:
  this is the reference's own rule (`SuperSwingTimer_State.lua:1516-1536`, "Auto Shot must
  not reset the MH swing when the Hunter is at range; only reset MH/OH when the target is
  actually in melee range"). The melee test reuses main.lua's `in_melee_range`
  (`main.lua:2462-2477`, exact-yard based) and falls back to one `st.api.UnitDistance`
  read; unknown counts as not-in-melee, and the probe is throttled to 0.25 s.
- Writes the one field the engine tests (`unit.preventSwingReset = true`). The lib clears
  it on every SUCCEEDED (`lib:636`) and recomputes it on every START (`lib:684`), so it
  cannot stick; worst case is one suppressed reset.
- Classic line only (`swing_engine == "vendored-lib"`); Forever's `swing_source` has no
  cast-reset branch and Retail runs the inert stand-in.

Real-engine proof of the guard, same harness, `preventSwingReset` armed mid-cast exactly
as the class hook now does:

```
Auto Shot SUCCEEDED with preventSwingReset=true:
    SWING_TIMER_START hand=ranged      (only)
    (unit.preventSwingReset after SUCCEEDED: false)
Auto Shot SUCCEEDED with the flag left to the lib (control):
    SWING_TIMER_START hand=mainhand
    SWING_TIMER_START hand=offhand
    SWING_TIMER_STOP hand=ranged
    SWING_TIMER_START hand=ranged
```

That control/proof pair is pinned in `tests/hunter_state.lua` §14m against the real
library, and the stub-engine contract in §14l. Mutations M2/M3 (§8) kill both.

**UNTESTED IN CLIENT:** whether the client fires `UNIT_SPELLCAST_START` for Auto Shot on
Anniversary (the guard keys off the engine's `casting` flag, which shares that
precondition, so a client that never reports the cast also never fires the reset). The
0.5 s Auto Shot cast is operator-confirmed on both classic-line clients (workshop lesson
17) and the reference's own cast-bar gate reads Auto Shot through `UnitCastingInfo`
(`SuperSwingTimer_UI.lua:482-515`). In-client close-out: `/st diag`'s
`swing_mainhand` counters should show NO START at range while auto-shooting, and climb
only on real melee hits.

---

### 4.4 Verification of the wave's follow-up lead (second pass, same day)

Lead under test: *"Auto Shot 75 is in `noreset_swing_spells` (e.g. `:1030`), so Auto Shot
itself is exempt; but hunter shot casts (Steady/Multi/Aimed) are not, so each shot may
restart the melee bars."*

**Verdict: the mechanism is CONFIRMED; the exemption claim is REFUTED.**

Static (current tree): **no `[75]` entry exists in ANY `noreset_swing_spells` table.**
The six bands are `996-1044` (isClassic), `1115-1167` (isBCC), `1380-1448` (isWrath),
`1525-1560` (isCata), `1629-1668` (isMists), `1703-1713` (isRetail). Every
`[75] = true, -- Auto Shot` line (`:1051`, `:1176`, `:1466`, `:1572`, `:1588`, `:1679`,
`:1722`) sits inside a **`ranged_swing`** table - the table that STARTS the ranged swing
on Auto Shot's `SUCCEEDED` (`:606-612`), the opposite of an exemption. The cited `:1030`
in the pre-edit file was `ranged_swing[75]`; that file's `noreset` band ended at `:1023`.

Dynamic (real `Libs/LibClassicSwingTimerAPI`, real LibStub + CallbackHandler, the branch
tables each client actually selects; `casting`/`preventSwingReset` read at START):

| Branch (globals) | token | `casting` | `preventSwingReset` | events at SUCCEEDED |
|---|---|---|---|---|
| Era (2, 0) | Auto Shot 75 | true | **false** | `START:mainhand, START:offhand, START:ranged` |
| Era (2, 0) | Steady 34120 | true | false | `START:mainhand, START:offhand` (no Steady on Era) |
| Era (2, 0) | Aimed 19434 / Multi 2643 / Arcane 3044 | true | true | none |
| Anniversary (5, 1) | Auto Shot 75 | true | **false** | `START:mainhand, START:offhand, START:ranged` |
| Anniversary (5, 1) | Steady 34120 | true | true | none |
| Anniversary (5, 1) | Aimed 19434 / Multi 2643 / Arcane 3044 | true | true | none |
| Titanforge (11, 2) | Auto Shot 75 | true | **false** | `START:mainhand, START:offhand, START:ranged` |
| Titanforge (11, 2) | Steady 34120 | true | true | none |
| Titanforge (11, 2) | Aimed 19434 / Multi 2643 / Arcane 3044 | true | true | none |

Readings:

1. **`unit.casting` IS set by the Auto Shot cast, and Auto Shot is NOT exempt on any
   branch** (`preventSwingReset` false at its START because 75 is in no table), so the
   reset branch fires mainhand + offhand + ranged. This is the leak, and it is the only
   one left on the current tree. Coverage argument independent of the client payload:
   `casting` is set ONLY by the lib's own `UNIT_SPELLCAST_START` (`lib:683`) and
   `CHANNEL_START` (`lib:708`), and the reset branch tests exactly `unit.casting`
   (`lib:596`) - so a client that never reports the Auto Shot cast also never reaches the
   reset. The guard's trigger and the defect's trigger are one and the same flag.
2. Steady Shot is exempt on Anniversary and Titanforge (it always was); Era shows the
   non-exempt path only because Era has no Steady Shot. **"Steady leaks" is refuted.**
3. Multi/Aimed/Arcane/Serpent are exempt on all three branches **as of the lib lane's
   2026-10-25 hunter-shot change**; before it, Aimed leaked on Era and BCC (first-pass
   run). The lead's statement was true for Aimed at wave start, stale by the time of this
   pass.
4. The branch discriminator is real: Steady's answer differs between Era and
   BCC/Titanforge, which proves the per-version table selected is the right one.
5. **`st.family` does not select the lib branch.** The lib reads `WOW_PROJECT_ID` +
   `LE_EXPANSION_LEVEL_CURRENT` at load (`lib:44-54`); `st.family` is compat's parallel
   label derived from the same globals plus a TOC fallback (`compat.lua:38-99`). A client
   where the globals are absent but the TOC is known can label `family = ERA/TBC` while
   the lib's tables stay empty - the `exp_level == nil` tolerance (`lib:46-52`) covers the
   Anniversary-nil shape, not a nil `WOW_PROJECT_ID`.

**Fix options, as the lead asked (lib vs main.lua) - both rejected, the shipped guard is
the minimal in-scope fix:**

| Option | Verdict |
|---|---|
| lib: add 75 to each per-version `noreset_swing_spells` | **REJECTED.** It also suppresses the in-melee reset, which the reference deliberately keeps ("Auto Shot must not reset the MH swing when the Hunter is at range; only reset MH/OH when the target is actually in melee range", `SuperSwingTimer_State.lua:1516-1536`). It is also a `Libs/` edit (HU-29), and the lookup is a raw table key on the event's `spell` argument - a payload that carries the localized NAME (the TBC shape for state APIs, UNVERIFIED for `UNIT_SPELLCAST_SUCCEEDED`) would silently miss a numeric-id entry, whereas the class guard matches id OR name. |
| main.lua: snapshot at cast start, restore at SUCCEEDED | **REJECTED.** A cast-reset START is payload-identical to a real swing START (`SwingStart` fires the same unitId/speed/expiry/hand for both; `isReset` only suppresses the STOP), so a restore needs a timing heuristic that can eat a genuine melee swing landing inside the same frame. |
| shipped: class guard arms the engine's own `preventSwingReset` | **SHIPPED**, real-lib-proven, 2 mutations (M2/M3) kill it. No heuristic, no lib edit, no main.lua edit; the engine still makes the reset decision, and in melee nothing is armed. |

No further code change results from this lead. One design question remains for the
operator (see §10, "open question"): whether an Auto Shot cast **at melee range** should
delay the melee swing (the reference rule this guard implements) or never reset melee at
all (the unconditional rule the lib now applies to the damage shots).

## 5. Task B — the standalone ranged-distance bar

### 5.1 Shape and contract

| Requirement | Implementation |
|---|---|
| Own top-level frame, not a swing-bar child | `CreateFrame("Frame", "SwedgeTimerWeaveRangeBar", UIParent)` — `weave_range.lua:249-299`; parent pinned by `tests/weave_bar_state.lua` ("TOP-LEVEL frame"). |
| Horizontal fill | fill is `SetPoint("LEFT")`, width drives the fill (`:274-281`); height 10 (`BAR_HEIGHT`). |
| Fill 1.0 at ≤ 5 yd, 0.0 at ≥ 35 yd (hunter) / 30 yd (others), linear | `NEAR_YARDS=5`, `HUNTER_FAR_YARDS=35`, `FAR_YARDS=30`; `fill_fraction` (`:123-145`). |
| Live yards + state word | `label` (`:200-210`) → `"12 yd  IN RANGE"`, `"3 yd  MELEE"`, `"40 yd  OUT"`. |
| Distance source: `st.api.UnitDistance("target")` ONLY | `:401-409`; the static contract in `tests/weave_range_state.lua` §0 forbids `LibRangeCheck`, `target_min_range`, `target_max_range`, `UnitDistanceSquared(`, `C_Timer`, `GetTime(` and every protected probe. |
| nil answer DELEGATED to `ST.weave_range_default_enabled(ST.player_class)` (HUNTER = true, others false), explicit false = OFF, explicit true = ON, class/global gates | `class_default_on` + `enabled_for` (`weave_range.lua:100-136`); pinned in both suites. This is the SAME reader the options getter falls back to (`option_tables.lua:195-224`), so the fresh-profile answer, a pre-key profile's nil answer, the settings UI and the runtime gate cannot disagree. No class token is hardcoded in the module: a helper that says off turns a hunter's nil off (delegation pins in `tests/weave_bar_state.lua`). |
| Disabled/unknown/no-target: no distance reads, frame hides | Gate order in `update` (`:369-421`); pinned by "the disabled path never reads the distance" and "no target: the distance is never read" (mutation M6 kills 6). |
| Unknown never paints 0 | `fill_fraction` returns **nil** (not 0) for an unknown distance (`:124-126`); `update` hides (`:412-416`). Mutation M5 turns that into a painted 0 and 3 pins go red. |
| Anchor above the ranged bar, screen-clamped, centre fallback only without a ranged bar | `layout` (`:316-367`): `BOTTOMLEFT` on the ranged bar's `TOPLEFT`; reserves the cast bar + Rapid Fire stack by HEIGHT (never visibility — a visibility-driven offset would repeat the §3 defect); clamp shifts the bar down by the overflow past `UIParent` top − 4. |
| Stale header comment fixed | `:1-44` rewritten (horizontal, hunter-ON, UnitDistance-only, no band fallback). |
| No measurable cost when hidden | One driver frame; the OnUpdate is an add + compare per frame; the gate pass runs at 0.05 s while enabled and **0.5 s while disabled** (`DISABLED_INTERVAL`), and the disabled path touches no unit API. Every paint value is latched. |
| Guarded driver | `poll` (`:454-478`) pcall-isolates, announces once, quarantines after 25 throws (pinned). |

### 5.2 What was removed and why

The old module had a LibRangeCheck **band fallback** (`is_known`, `distance_proxy`,
`proximity_fraction(min,max)`, `format_yards(min,max)`) and a vertical left-of-PlayerFrame
frame. HU-23 rules the band path out (operator: exact yards only), so those helpers are
gone rather than left dead; the static contract in the suite now fails if any of them
returns. The 4-state `hunter_ui` strip is untouched (§10).

---

## 6. Options copy owed to the appearance-options lane (`option_tables.lua`, not my file)

The shipped widget (`option_tables.lua:195-220`) keeps the key and name but its `desc` is
now factually wrong ("banded where it only has range checks"). Exact replacement:

```lua
    self.opts_table.args.weave_range_enabled = {
        type = "toggle",
        order = 1.13,
        name = "Ranged distance bar",
        desc = "Show the standalone horizontal ranged-distance bar: it fills as the "..
            "distance to your attackable target closes to melee (full at 5 yd or "..
            "closer) and drains as the target moves away, labelling the exact distance "..
            "in yards plus MELEE / IN RANGE / OUT. It hides when there is no attackable "..
            "target or the client cannot answer a distance, so an empty bar means "..
            "unknown, never zero. ON by default for hunters (35 yd band, Auto Shot "..
            "range); every other class opts in here (30 yd band).",
        get = ... -- unchanged (saved value wins, else ST.weave_range_default_enabled)
        set = ... -- unchanged
        disabled = ... -- unchanged
    }
```

Also owed (main.lua owner, not my file): `main.lua:985-990`'s comment still says the bar
"stays invisible until the class's weave_range_enabled toggle is on (off by default)" and
"creates its hidden frame and driver here" — the default is now hunter-ON/nil-safe and the
module drives itself from `poll()`; the `init(self)` call itself is correct and unchanged.

---

## 7. Other-lane / orchestrator items

1. **`tests/run.sh` (orchestrator):** register the new suite with
   `run "lua5.1 tests/weave_bar_state.lua" lua5.1 tests/weave_bar_state.lua`.
   `tests/toc_check.lua` currently reports 4 unregistered suites; three are other lanes'
   (`appearance_defaults_state`, `engine_matrix_state`, `practice_timeline_state`), the
   fourth is this new file. Until they are registered `bash tests/run.sh` fails the
   registry pair, which is not a defect in the suites.
2. **`tests/bars_state.lua` (mine, stated loudly):** the pin at the old `:2175-2184`
   asserted `ui.melee_anchored == true` and that hiding the cast bar issued
   `LibWindow.RestorePosition`. That contract is deliberately gone (§3), so the pin is
   re-cut to the inverse: a visible cast bar and its hide must move no melee bar. The old
   code makes the new pin fail (mutation M1, 2 red pins); nothing else in that suite
   changed.
3. **The lib lane's parallel change is compatible, and the two halves do not overlap:**
   their `noreset_swing_spells` additions exempt Multi/Aimed/Arcane/Serpent; Auto Shot 75
   is deliberately left out and delegated to this class guard (their comment names
   `classes/hunter.lua suppress_auto_shot_melee_reset`). Their edit moved the line numbers
   my comments cite, so `classes/hunter.lua:737-763` cites the branch by its `casting and
   not preventSwingReset` form plus current line numbers, not a frozen range.
4. **`nextaction_ui` C3 (out of scope, already filed):** the hunter guide is gated on the
   mainhand swing cycle, so it stays hidden at range. Unchanged by this work.

---

## 8. Verification

Focused suites (baseline is red on the LibRangeCheck steps, which are another lane's):

```
lua5.1 tests/real_wire_state.lua     978 checks, 0 failures (2 expected-fail, HU-29)
lua5.1 tests/weave_range_state.lua   83 checks, 0 failures
lua5.1 tests/weave_bar_state.lua     96 checks, 0 failures   (NEW)
lua5.1 tests/hunter_state.lua        PASS 1824 checks (was 1796: +28 for §14l/§14m and 14d)
lua5.1 tests/hunter_guide_state.lua  PASS 1976 checks
lua5.1 tests/hunter_window_state.lua PASS  213 checks
lua5.1 tests/bars_state.lua          PASS  956 checks
luacheck (touched files)             0 warnings / 0 errors
```

`bash tests/run.sh` deliberately NOT run (orchestrator owns it).

Mutation proofs, each on a fresh `/tmp/opencode/mut` copy of the tree (`rsync` without
`Media/`, `docs/`, `.git`), restored between runs, copy deleted afterwards:

| # | Mutation | Result |
|---|---|---|
| M1 | `hunter_ui.lua` reverted to `git HEAD` (the re-anchor restored) | **9 red**: 7 `hunter_state` (mainhand −129/want −142, offhand −145/want −158, two restore-count pins, the live-cast pair) + 2 `bars_state` (Lwin restores issued by a visible/hidden cast bar) |
| M2 | `unit.preventSwingReset = true` commented out in the guard | **8 red**, incl. the REAL-engine leg ("got START:mainhand,START:offhand,STOP:ranged,START:ranged") |
| M3 | in-melee rule inverted (`== false`) | **6 red** (range arms nothing, in-melee arms) |
| M4 | `HUNTER_FAR_YARDS` back to 30 | **5 red** (3 `weave_bar_state` fill/label maths, 2 `weave_range_state` band pins) |
| M5 | unknown distance coerced to 0 | **3 red** (bar shows, fill repaints, label repaints) |
| M6 | distance read moved above the enable gate | **6 red** (every disabled-path read pin) |
| M7 | `DISABLED_INTERVAL` collapsed to 0.05 | **4 red** (both suites' cadence pins) |
| M8 | nil rule hardcoded back to `player_class == "HUNTER"` (the pre-contract shape) | **5 red** (3 pure `class_default_on` pins + 2 frame delegation pins, incl. the no-distance-read-on-off assertion) |
| M9 | the config helper never consulted (default always off) | **6+ red** (hunter-nil show, distance read, cadence, fill, label + the pure helper pins) |

---

## 9. Cross-client matrix

| Family | Engine guard (`suppress_auto_shot_melee_reset`) | Distance bar |
|---|---|---|
| Classic Era 1.15.9 | active (`swing_engine == "vendored-lib"`); the same fixed lib path proven above runs on the Era tables (`isClassic`). | `UnitDistanceSquared` documented (`UnitDocumentation.lua:610`, branch `classic_era`); hunter band 35 yd. |
| TBC Anniversary 2.5.6 | active; the real-lib proof in §4 used the BCC tables (`project 5`), i.e. this exact client line. | same documentation (`classic_anniversary:UnitDocumentation.lua:610`). |
| Titanforge 3.80.2 (WotLK) | active; `isWrath` tables. Note the lib's Wrath arm also re-arms `ranged` on a melee hit (`lib:409-417`) — intended there, untouched. | documented (`classic_titan:UnitDocumentation.lua:610`). |
| WoW Forever 1.60.1 | inert by the `swing_engine` gate: `swing_source.lua` has no cast-completion reset to guard. | documented (`origin/forever:UnitDocumentation.lua:1108`). |
| Retail 12.1.x | inert: the inert stand-in never reports a swing (`main.lua:36-44`). | documented (`live:UnitDocumentation.lua:1080`); with no ranged bar the bar falls back to the UIParent centre. |

`ST.player_class` is `UnitClass`'s second return on every family, so the hunter band and
the hunter nil-enable rule follow the played class, not the client version. Nothing in
either change branches on `st.is_mainline` (workshop rule): the engine string and the
client's own distance answer decide.

## 10. Findings, not fixed (evidence + recommendation)

- **OPEN QUESTION for the operator (melee-weave feel, not a bug):** should a completed
  **Auto Shot cast at melee range** delay the melee swing? The shipped guard follows the
  reference (`SuperSwingTimer_State.lua:1516-1536`) and lets the reset happen in melee;
  the lib's new unconditional exemptions for the ranged damage shots say "a shot never
  resets melee". The two rules are defensible and currently split by design; if the
  operator wants "no hunter shot ever resets melee", the guard's melee branch is a
  one-line change (`if self.hunter_autoshot_guard_melee == true then return end` removed).
  Archived as a hands-up signal; nothing is blocked on it.
- **The 4-state range-helper strip now overlaps the new bar in purpose.** Both are
  hunter-on by default; both gate on an attackable target; both use a 5 yd melee edge;
  the strip adds only the 5-10 yd "sweet spot" band and a colour, from
  `IsSpellInRange(Wing Clip / Raptor Strike / Auto Shot)` plus one `UnitDistance` read
  (`hunter_ui.lua:857-918`). Recommendation: keep it for the sweet-spot band, or retire
  it in a later wave on operator order (removing it also removes 3 spell-range probes per
  frame). Not removed here: a default-visible widget is the operator's design call.
- **`hunter_ui.update_range_helper` reads exact yards independently of the new bar**
  (`hunter_ui.lua:896-901`) — one extra `UnitDistance` per frame while the strip is on.
  Folding the strip onto the new bar's cached reading is a cheap follow-up if the strip
  stays.
- **`classes/hunter.lua` still holds `hunter_autoshot_guard_count`** (a write-only
  counter, like the pre-existing /st diag counters) — `diag.lua` is out of scope, so the
  counter is not surfaced yet. File for the diag owner if the guard ever needs a receipt
  line.

## 11. In-client checks owed (the only proof that counts)

1. Hunter at range, auto-shooting, no melee: the mainhand bar must NOT sweep with the
   Auto Shot cycle, and it must not move toward the ranged bar. `/st diag`'s
   `swing_mainhand` START count should stay flat between real melee swings.
2. Melee weaving: a real mainhand swing (Raptor Strike / white hit) must start the
   mainhand bar exactly as before, and the offhand bar must follow its own weapon.
3. The distance bar: full at melee, empty past 35 yd, label + word legible at the
   operator's UI scale; the bar sits above the cast bar/Rapid Fire stack without
   overlapping either, and stays on screen with the ranged bar near the top.
4. `/st diag` after a session: `callback_errors=0`, `bar_hook_errors=0`; no
   `ADDON_ACTION_BLOCKED` from the range path (the bar only calls `UnitDistanceSquared`
   through compat).
