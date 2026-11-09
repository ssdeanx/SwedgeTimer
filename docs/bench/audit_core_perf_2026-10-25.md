# Core performance + reliability audit (2026-10-25, desk `audit-core`)

READ-ONLY scope, no product file touched:
`main.lua`, `bars.lua`, `compat.lua`, `swing_source.lua`, `guard.lua`,
`utils.lua`, `diag.lua`, `ldb.lua`, `enemy_swing.lua`, `hud.lua`,
`config.lua`, `config_presets.lua`.

Operator ask (verbatim intent, 2026-10-25): *"deep audit of my current addon,
make sure you check actual code ... scan it for other improvements to
performance, reliability and more ... brainstorm ideas for any other things we
could improve, optimize, and enhance."*

## Skills + method

@bench-read: `desks/journal.md` (lane table + the 2026-10-25 wave dispatch and
pre-reconcile findings), `bench/lessons.md`, `bench/audit_core_2026-10-22.md`,
`hands-up.md` HU-23/24/29/31/32. @desk-open: `desks/audit-core/` (journal +
`.signals/`), worked there only. @desk-journal + @signal-write at close.

Method: full read of every in-scope file (11,545 lines), every per-frame path
traced to the frame that installs it; every registration counted; every cache
checked for a cap; cross-client claims verified against
`/home/sam/wow-ui-source` by branch (`git show` / `git grep`) with
branch:path:line; client behaviour that is not in FrameXML (OnUpdate on hidden
frames) cited to the wiki.

**Snapshot caveat.** The tree moved under this audit: other lanes in the same
wave edited `main.lua`, `swing_source.lua`, `config.lua`, `config_presets.lua`
while I was reading. MD5 before → after:

| file | before | after |
|---|---|---|
| main.lua | e2442ccc… | 7b3a617b… (+11 lines in `print_runtime_diag` only) |
| swing_source.lua | 8ee8efb5… | de1d4aad… → 450cff58… → 48988f49… (the cross-client lane is still editing this file; every citation below was re-grepped at 48988f49. The `cycle.start` gap noted in §5.3 was fixed there mid-audit.) |
| config.lua | 3b0a52aa… | e7c105db… |
| config_presets.lua | 15443553… | be33d3f8… |
bars/compat/guard/utils/diag/ldb/enemy_swing/hud were unchanged throughout.
Every line number below was re-grepped against the **after** state. Nothing in
this report is a claim that the current wave introduced a defect unless it says
so; all findings are **pre-existing** in HEAD.

---

# 1. Per-frame cost

## 1.1 Every driver that exists, and whether it ticks when nothing is happening

| # | driver | where | cadence | runs when idle? |
|---|---|---|---|---|
| 1 | bar `OnUpdate` | `main.lua:876` installs `bars.lua` `onupdate_common` on the **bar_frame** | every frame | **No** — hidden frame ⇒ engine does not call OnUpdate (`warcraft.wiki.gg/wiki/UIHANDLER_OnUpdate`: "Blocked by hiding a frame or its parent"). Default visibility is `show_behaviour="conditional"`, `show_condition="either"` (`config_presets.lua:136-138`), so out of combat with no attackable target the bar is hidden and the tick stops. **On when visible but idle** (full cycle, between swings). |
| 2 | HUD driver | `hud.lua:649-658` | every frame, throttle `TICK=0.05` (`hud.lua:97`) | **Yes — always.** The frame is explicitly "never hidden" (`hud.lua:647`). Ticks even when the row is hidden, when `hud_enabled=false`, and while out of combat (default `hud_visibility_key="always"`, `config_presets.lua:41`). |
| 3 | HUD layout poll (2nd driver) | called from the class hook every bar tick → `HUD.on_bar_update` (`hud.lua:697-715`) | every bar tick, **not throttled** | **Yes, per frame, per hand.** Paladin/warrior/rogue/druid/shaman reach it once per frame (mainhand gate); hunter reaches it twice (ranged+mainhand, `classes/hunter.lua:1026`). |
| 4 | enemy-swing bar | `enemy_swing.lua:409` | every frame while shown | No — hidden outside combat/without a tracked target (`enemy_swing.apply_visibility`). |
| 5 | range poll | `main.lua:2501-2532` (`C_Timer.After` re-arm) | 20 Hz | **Yes — always, from init to logout**, no target, out of combat, bars hidden, options closed. |
| 6 | TBC aura poll | `main.lua:1028-1051` | 20 Hz | **Yes on the TBC family**, from `post_init` to logout (`main.lua:1008`). |
| 7 | LDB feed | called from bar tick (mainhand only), `ldb.lua:197` | every frame, throttled 0.25 s | Only with a mainhand bar tick. |
| — | out of scope, same pattern | `weave_range.lua:184`, `rotationtext.lua:563`, `nextaction_ui.lua:433`, `practice_ui.lua:2250` | — | These are 4 more driver frames owned by other lanes (consolidation idea: §9 item 8). |

## 1.2 `bars.lua:onupdate_common` — cost per invocation, and per second

Traced top to bottom (`bars.lua:747-925`). Counts are **calls per tick**, from
the code; "per second" assumes 60 FPS and one visible hand.

| work | line | per tick | per s @60fps | note |
|---|---|---|---|---|
| `bar_is_built` → 2 getters | 748, 754 | 2 calls, 4 table reads | 120 / 240 | |
| `st.api.get_time()` | 762 | 1 C call | 60 | |
| `get_hand_table` chain (`get_class_table`→`db.profile[class][hand]`) | 763 | 1 (≈5 reads) | 60 | |
| progress math | 790-791 | `math.max/min` ×3 | 180 | |
| bar fill | 799-800 | `SetWidth` + `SetTexCoord` | 120 C calls | needed |
| **spark** | 804-818 | `SetSize`, `ClearAllPoints`, `SetPoint`, `convert_color` (4 div + unpack), `SetVertexColor`, `Show` | **300 C calls + 60 table unpacks** | **all but Show are constant** — see O2 |
| flash `IsShown` | 822 | 1 C call | 60 | |
| GCD underlay | 836-838 | when `gcd.expires` set: `set_gcd_width` (+`bar_is_built`, `get_visuals_frame`, `get_hand_table`, 3-5 C calls) | 0-300 C calls | during a GCD only |
| GCD markers 1a/1b | 842-897 | `get_gcd_marker_duration` → `get_hand_table` **again**, then `SetStartPoint`+`SetEndPoint` each | up to 180 C calls + 120 Lua | only when anchored to `swing` |
| `set_bar_texts` | 900 | see below | — | |
| class hook `st.guard.run` | 905-909 | `"class:" .. tostring(class) .. ":on_bar_update"` (**1 new string**), `tostring` ×2 inside `guard`, `pcall` | 60 strings + 180 tostring + 60 pcall | |
| zones | 912-914 | 1 table read (none registered today) | 60 | dormant |
| ldb guard | 919-924 | `guard.run` + `ldb.update` → `api.get_time()` + throttle compare | 60 pcall + 60 clock | mainhand only |

`set_bar_texts` (`bars.lua:1197-1288`), called once per tick:

| work | line | per tick | per s | note |
|---|---|---|---|---|
| `bar_is_built` + `get_visuals_frame` + `self[hand]` | 1198-1205 | 3 calls | 180 | |
| `st.api.get_time()` **again** | 1219 | 1 C call | 60 | the tick already has `t` |
| `get_hand_table` **again** | 1217 | 1 | 60 | |
| `lookup = { attack_speed = …, swing_timer = … }` | 1223-1228 | **1 table + up to 2 `string.format`** | 60 tables + 120 strings | values change ~10×/s |
| `needs_range_string` → `get_hand_table` **again** | 1230, 1185 | 1 | 60 | |
| `SetText` left/right (+`Hide` centre) | 1253, 1267, 1281 | 2 `SetText` + 1 `Hide` | 180 C calls | text changes ~10×/s |

**Derived total, one visible bar (normal cycle, defaults):**
≈ 660-1,000 C widget calls/s, ≈ 180 clock calls/s (60 tick + 60 text + 60 LDB),
≈ 120 table allocations/s (60 `lookup` + 60 guard-site keys), ≈ 180 string
allocations/s (120 `string.format` + 60 guard-site keys). Three hands ⇒
≈ 2,000-3,000 C calls/s. This is not a crisis; it is pure waste on a 60 FPS
frame budget, and it trips GC twice a second for no visible change.

**Hidden-frame ticks:** correctly zero for the bar and enemy-swing frames (see
§6). The HUD is the exception.

## 1.3 HUD per-tick (the heaviest path in scope)

`HUD.on_update` (`hud.lua:1378-1414`), driver frame, **every frame**:

- `get_class_table()` at `hud.lua:1387` — **before** the 0.05 s throttle at
  1394-1397. One profile chain per frame for nothing.
- at 20 Hz: `layout_changed` (1403) then `should_show` (1407) then
  `update_display` (1413) when visible.

`HUD.on_bar_update` (`hud.lua:697-715`) adds a **second, unthrottled** layout
poll per bar tick:

- `HUD.layout_changed` (`hud.lua:1056-1079`) = 13 `db[key]` reads
  (`LAYOUT_KEYS`, 125-129) **plus** `HUD.icon_should_show` per icon
  (`hud.lua:755-766`);
- for each trinket slot that is `icon_should_show` calls `HUD.trinket_usable`
  (763) with no cached `use_enable` → `trinket_has_on_use` (`324-330`) →
  `api.GetInventoryItemCooldown` = **one live client call per trinket per
  poll**.
- Paladin HUD has exactly two trinket slots (`classes/paladin.lua:3838-3839`).

So a paladin pays **60 layout polls/s + 120 `GetInventoryItemCooldown` calls/s**
while the HUD is hidden and out of combat; the driver adds 20 polls + 40
inventory reads; hunter (two hands reaching the hook) pays ~240 inventory
reads/s. On-use capability is **a property of the item**, not of time.

`HUD.update_display` (20 Hz, visible only) per tick:

- 2 × `HUD.trinket_state` (1291) → `scan_trinket_proc` (`303-317`) = an aura
  walk up to `AURA_SCAN_LIMIT = 40` (`hud.lua:100`) **per trinket**, each row
  through `api.UnitAura`, which runs `aura_entry_is_secret` = 10 `is_secret()`
  calls on every row (`compat.lua:530-535`);
- `HUD.spell_known_allows` per visible spell icon (`1306-1307`, `816-839`) →
  `api.is_spell_known_state` (`compat.lua:261-290`): 1-3 **pcalled** client
  probes per icon, per tick, forever;
- `HUD.paint` per icon (1111) → `get_class_table()` again per icon (1116).

With ~10 player buffs: ≈ 21 aura wrapper calls + ~210 `is_secret` calls +
4-12 spell-known probes per tick ⇒ **≈ 500 client calls/s and ≈ 5,000 Lua
calls/s continuously on a paladin, HUD idle, out of combat**. Worst case at the
40-row cap and two trinkets is ~1,600 aura reads/s.

The HUD's paint itself is a *good* pattern: swipe, texture, text, tint and glow
are all change-gated (`hud.lua:1121-1219`). The cost is the polling around it.

## 1.4 idle non-bar paths

- **Range poll** (`main.lua:2501-2532`): 20 × (`pcall` → `api.UnitDistance` →
  `pcall(UnitDistanceSquared)` → 2 `is_secret` → `sqrt`) + 20 ×
  `set_bar_visibilities` + 20 × `handle_oor`.
  `set_bar_visibilities` (`2660-2682`) per hand: `bar_is_enabled` +
  `handle_bar_visibility` + a full `show_bar`/`hide_bar`
  (`get_class_table`, `check_bar_enable_settings`, `get_bar_frame` ×2,
  `Show()` ×2) — ≈ 40-70 Lua ops and 2-4 C calls per hand **per 50 ms, every
  50 ms, forever**, even when every bar is disabled (the disabled branch still
  calls `hide_bar`, `main.lua:2667-2672`).
  Derived: ≈ 2,400-4,200 Lua ops/s and ≈ 120-240 C calls/s at idle with three
  hands — for a pass whose *inputs* changed zero times.
- **`handle_oor`/`handle_oor_hand`** (`2537-2567`): per hand, `SetAlpha(1.0)`
  or `SetAlpha(db.dim_alpha)` every 50 ms — the same value 20×/s.
- **TBC aura poll** (`1040-1051`): 20 × `class_on_aura_change`. On paladin that
  is `classes/paladin.lua:714` → `parse_seals` (513) which walks **all 40 aura
  rows unconditionally** (`classes/paladin.lua:590-600`, "no early break") →
  **800 `api.UnitAura` calls/s and 8,000 `is_secret` calls/s on TBC, in or out
  of combat, bar hidden or not.** The TBC client is the operator's primary
  target (per project memory), so this is the single largest idle cost found.
- **enemy_swing** (`enemy_swing.lua:586-592`): despite being **off by default**
  (`config.lua:34`), its driver frame is created at load and registers CLEU
  (`644-676`); every CLEU event runs `get_addon()` = `LibStub("AceAddon-3.0",
  true)` + `:GetAddon` (`267-273`) before reading the toggle. A 25-man pull
  produces hundreds to ~1,000 CLEU/s; that is ≈ 5,000-20,000 wasted Lua ops/s
  on every classic client with a feature the user never enabled.

---

# 2. Event-path cost

## 2.1 Registrations

`main.lua` registers **30** events (`652-726`). All 30 exist on `live` except
`PLAYER_TARGET_SET_ATTACKING`, which is correctly family-gated
(`main.lua:685-691`) — verified against
`live:Interface/AddOns/Blizzard_APIDocumentationGenerated/*` (every other name
has a `LiteralName` entry). `START_AUTOREPEAT_SPELL` is validity-probed
(`671-681`); it exists on all five branches.

**11 of the 30 are unit events that only care about the player**
(`UNIT_AURA` 695, `UNIT_POWER_FREQUENT` 699, `UNIT_TARGET` 725, and 8 ×
`UNIT_SPELLCAST_*` 713-724) — but AceEvent registers them **unfiltered**:
`AceEvent.events:OnUsed` calls `AceEvent.frame:RegisterEvent(eventname)`
(`Libs/AceEvent-3.0/AceEvent-3.0.lua:31-38`), i.e. every raid member's aura,
power, target and cast events are dispatched into Lua and then dropped by a
`unit_id ~= "player"` check at the top of each handler (`1847-1852`,
`1854-1868`, `2176-2182`, `2848-2858`). In a 25-man raid that is the largest
avoidable dispatch volume in the addon (hundreds of events/s; `UNIT_AURA` alone
scales with 25 units × their aura churn).
Caveat: `UNIT_SPELLCAST_START` also feeds the pre-pull clock from the
**target** (`main.lua:2130` → `update_pull_clock`, needs `unit_id=="target"`),
so it must stay player+target, not player-only.

The project already had the right shape: the archived build registered
`st.player_frame:RegisterUnitEvent("UNIT_AURA","player")` and the cast events
player-only (`docs/swedge/SwedgeTimer_TBC/main.lua:104-115`). The current build
regressed to AceEvent's unfiltered path. `RegisterUnitEvent` is documented on
every branch (`classic_era:…/SimpleFrameAPIDocumentation.lua:943`) and
Blizzard's own classic code registers two units
(`classic_era:…/Blizzard_BuffFrame/BuffFrame.lua:285`), so
`("UNIT_SPELLCAST_START","player","target")` is a supported shape.

**CLEU listeners on a classic client:** `main.lua:710-712` (all classes,
deliberate per G2), `enemy_swing.lua:655` (even when the feature is off —
always), and `hud.lua:615-644` whenever the class has any trinket slot
(paladin always: `classes/paladin.lua:3838-3839`).
Main's listener does the most work per event: `UnitGUID("target")` **per event**
(`main.lua:1071`), 2 × `select` for the GUIDs (`1073-1074`), then the
neutral pre-pass with 5 × `select` (`1091-1092`).

**Duplicate/pointless registrations:** `PLAYER_ENTERING_WORLD` in `main.lua:656`
has an empty handler (`1562-1566`); `SPELL_UPDATE_COOLDOWN` (`670`),
`START/STOP_AUTOREPEAT_SPELL` (`679-680`) and
`PLAYER_STARTED/STOPPED_MOVING` (`668-669`) are consumed only by hunter code
(`classes/hunter.lua:734`, `772`; `hunter_ui.lua:836`) yet are registered for
every class.

## 2.2 Dispatch cost

- `ST.callback_event_handler` (`main.lua:1157-1224`) runs for **every** swing
  engine event. The stripped branch builds `local args = { ... }` (1186) and
  calls `pcall(handler, ST, event, unpack(args, 2, n))` (1207); the guard
  `event:sub(1, 12) == "SWING_TIMER_"` allocates a string on every event (1183).
  `select(2, ...)` would drop the first argument with no table at all.
- Per swing cycle the engine fires START + STOP (STOP also fires at every cycle
  end: `Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:204`), plus
  UPDATE on cast/attack-speed events. Each event = 1 `pcall` + (stripped) 1
  table + 1 string. Modest volume, trivial to remove.
- `ST:note_swing_wire` (`1312-1331`) allocates `{ hand, kind, t }` **per event**
  and reads the clock per event, purely for `/st diag`.
- `pcall` density in hot paths: bar tick → `guard.run` (1/tick); HUD tick →
  `guard.run` per icon (6-8/tick); `ldb.update` → 1/tick; range poll →
  `pcall` inside `rf_update` **and** `pcall` inside `api.UnitDistance` (double
  `pcall` for one `UnitDistanceSquared` read); `Update_pull_clock` → `pcall` per
  cast. Each is cheap individually; together they are the reason a "cheap" tick
  costs ~1,000 C calls/s (§1.2).

## 2.3 `C_Timer` churn

| site | object created | rate | cancelled? |
|---|---|---|---|
| `main.lua:2531` (range re-arm) | 1 timer + 1 closure | **20/s forever** | n/a (re-armed) |
| `main.lua:2524` (range retry) | 1 timer + 1 closure | on failure only | n/a |
| `main.lua:1050` (aura re-arm) | 1 timer + 1 closure | **20/s forever on TBC** | n/a |
| `main.lua:1498` (bar-full) | 1 timer + 1 closure | 1/SWING_TIMER_STOP | never cancelled; `bar.is_full_timer` is simply overwritten on the next STOP (`1498`) — see R5 |
| `main.lua:2111` (ranged fallback stop) | 1 timer + 1 closure | 1/Auto Shot on TBC fallback | superseded timer is cancelled (`2100-2105`) |
| `swing_source.lua:226` (Forever STOP grace) | 1 timer + 1 closure | 1/per swing | not cancelled; superseded by counter (`fire_stop_if_current`) |
| `main.lua:498` (init deadline) | 1 | once | — |

40 timer objects + 40 closures per second on TBC (20 elsewhere), i.e.
**72,000-144,000 timer allocations per hour of play** for two fixed 20 Hz
polls. `C_Timer.NewTicker(seconds, callback, iterations?)` is documented on
every branch (`classic_era:…/UITimerDocumentation.lua:21-28`) and fires the
same callback without re-arming. Note the harness pins the current shape:
`tests/main_init_state.lua:1393-1470` (§11a/11b) asserts 2 captured
`C_Timer.After` timers at 0.05 s and the re-arm counts, and
`tests/range_source_state.lua` captures `after` timers. A ticker change must
re-cut those pins (one-writer rule: file the pin, do not edit another lane's
suite).

---

# 3. Unbounded growth

In-scope structures, with their cap or proof of bound:

| structure | where | cap |
|---|---|---|
| `ST.callback_errors[event]` | `main.lua:1212-1219` | keyed by engine event names (fixed set) |
| `ST.bar_hook_errors{count,by_site,quarantined,first_reported}` | `guard.lua:81-100` | keyed by site strings; sites are class/slot/zone ids (fixed) — **grows only if a future caller builds a site key from data** |
| `ST.swing_wire_counts` | `main.lua:1312-1330` | 3 hands × 3 counters |
| `ST.swing_wire_last` | `1330` | one table, replaced per event (churn, not growth) |
| `diag.error_ring` | `diag.lua:63, 546-552` | `ERROR_MAX = 8`, `table.remove` oldest |
| `diag.tick_sites` | `diag.lua:275` | 3 hands |
| `st.ldb.last_*` | `ldb.lua:60-63` | scalars |
| `HUD.trinkets` | `hud.lua:200` | 2 slots |
| `HUD.known_names` | `hud.lua:777` | keyed by spell ids of the class's slots |
| `HUD.layout_cache` | `hud.lua:1038-1054` | 13 keys |
| `HUD.icons` | `hud.lua:565-577` | one per validated descriptor (fixed) |
| `st.zones.list/by_id` | `bars.lua:623-693` | registration-time; duplicate ids rejected; **nothing registers a zone today** (`grep register_zone` = comment only) |
| `swing_reset_names` | `main.lua:1904-1930` | 15 ids |
| `compat.spell_known_probes` | `compat.lua:204-227` | ≤ 3 at load |
| enemy-swing `active_cycles` / `cycle_counters` / `stats` | `swing_source.lua:97-143` | 3 hands / fixed fields |

**Verdict: no unbounded growth in scope.** The other two histories the mission
names are outside this scope but were checked for a cap while grepping:
hunter shot log `SHOT_LOG_MAX = 200` with oldest-eviction
(`classes/hunter.lua:1234, 1260-1261`), practice history `HISTORY_LIMIT = 50`
(`practice_stats.lua:53, 380-381`). Both bounded.

One GC-churn note, not growth: `st.utils.print_msg` increments
`st.debug_counter` forever (`utils.lua:8`) and prints it in every message
(`utils.lua:17`).

---

# 4. Reliability / error paths

## 4.1 The big one — the visibility driver is hosted inside the range poll

`set_bar_visibilities()` is called from exactly **one** automatic site:
`main.lua:2529`, after a successful `update_range_state` inside `rf_update`.
Every other visibility call is user/option/practice-driven: the options setters
call `handle_bar_visibility` per hand (`option_tables.lua:161-187, 1540`),
practice start/stop calls `show_bar`/`handle_bar_visibility` for the mainhand
(`practice_ui.lua:5646, 5712`), and the LDB click calls
`set_bar_visibilities` (`ldb.lua:133`).

`rf_update` returns **before** line 2529 in two reachable cases:

1. `self.rf_disabled` (`2502-2505`) — set by the designed dead-man after 3 poll
   failures (`2514-2518`, `2450-2460`). The M1 resilience path is pinned by
   `tests/main_init_state.lua:1269-1338`.
2. an error thrown in `set_bar_visibilities` / `handle_oor` — both are **outside**
   the `pcall` block (`2508-2526` covers only `update_range_state`; `2529-2530`
   are bare). A throw there escapes the `C_Timer` callback, and because the
   re-arm is the last line of the same function (`2531`), **the loop never
   re-arms**.

Either way, after the range poll stops, no code hides or shows a bar again on
combat/target/range transitions: the bars freeze in their last visibility
state (visible forever, or hidden forever) for the rest of the session, with
no notice except the range-disabled line. `handle_oor_hand` has a concrete
throw path for this: `frame:SetAlpha(db.dim_alpha)` (`main.lua:2560`) with no
type guard, and `db.dim_alpha` comes from the profile.

This is a structural defect, not a theoretical one: the designed M1 dead-man
guarantees a state where range display is off — and it silently takes bar
visibility with it.

## 4.2 Stale extra-attack suppression across a combat boundary

`ST:note_extra_attack_or_parry` counts `SPELL_EXTRA_ATTACKS` (`main.lua:1112-1117`).
On STOP with a pending count, the hand is **armed**
(`main.lua:1473-1476`), and the next START is consumed as "the extra" and
returns without touching the bar (`1400-1408`). Nothing ever expires or resets
`extra_attack_pending`, `suppress_armed` or `suppress_next_stop`:
`PLAYER_REGEN_ENABLED` (`1749-1761`) resets combat, the pull clock and class
hooks only, and no class module touches these fields (`grep` over
`classes/*.lua` = 0 hits).

Failure scenario: an extra attack (Sword Spec / Windfury / Thrash) is pending
when the fight ends (the killing swing, a target cancel, or the natural
cycle-end STOP at `Libs/…/LibClassicSwingTimerAPI.lua:204` followed by combat
exit). `suppress_armed[hand]` survives. The **next pull's first real swing is
swallowed**: the bar does not restart at that swing, and the following STOP is
swallowed by the tail branch (`1467-1480`). One full cycle (≈ 2-3 s) of a dead
bar on the pull, recurring whenever the trigger lands.

The asymmetry is the evidence that this is an oversight: the paladin resets its
own CLEU counter on combat exit with exactly this rationale
(`classes/paladin.lua:2214-2218`, "orphaned extra attacks must not carry into
the next fight"), while the bar-side state that actually suppresses the swing
is not reset. `tests/real_wire_state.lua:1763-1832` pins the in-fight shape and
nothing pins the boundary.

## 4.3 Swallowed pcalls / nil-return fallbacks that hide failure

- `main.lua:1203`, `1956`, `2103`: `pcall(function() timer:Cancel() end)` —
  swallowed (acceptable; the only consequence is a leaked timer, §R5).
- `main.lua:1742`: `pcall(api.UnitCastingSpell, "target")` — `ok` is checked,
  safe.
- `main.lua:1923`: `pcall(api.GetSpellInfo, spell_id)` in the reset-name cache —
  failure just omits a name; safe.
- `main.lua:2772`: `pcall(st.swing_source.diagnostic_text)` — diag-only.
- `hud.lua:628-644`: CLEU `RegisterEvent` failure **is** counted and announced
  once — correct.
- `bars.lua:46-57`: texture fetch falls back through `Minimalist` →
  `WHITE8X8` — correct, documented.
- `ldb.lua:67-73`: `pcall(string.format, …)` returns nil on a protected value
  and the field is not published — correct, documented.
- `compat.lua:905-921`: **`api.UnitAttackSpeed` / `api.UnitRangedDamage` return
  `0, 0` / `0` when the client lacks the global** (not `nil`). `check_weapons`
  then sets `has_weapon = false`, the offhand/ranged bars never build, and
  nothing reports that the API was missing. Fail-closed, but invisible. (No
  targeted client lacks the globals — UNVERIFIED for private clients.)
- `compat.lua:849-851`: `api.GetTalentInfo` unknown-client fallback returns
  rank `0`, which every caller reads as "talent not taken" — a silent wrong
  answer rather than "unknown". Same class of issue.
- `diag.lua` is pcall-per-field **by design** and reports "?" — correct.

## 4.4 Latches that never clear (audited, all deliberate except one)

`ST.swing_unknown_hand_notice_shown`, `enemy_swing.stats.reject_notice_shown`,
`HUD.cleu_register_notified`, `HUD.inert`, `st.guard` quarantine,
`ldb.init_attempted` — all one-per-session by design and announced.
The exception: `self.rf_disabled` (`main.lua:2455`) is terminal **and** carries
the §4.1 coupling; no retry exists (a single transient triple-throw kills range
+ visibility for the session). `ST.init_deadline_fired` is handled by the late
INFO rewire (`465-491`).

## 4.5 Init-order assumptions

- `init_libs` sets `interfaces_are_initialised = true` at `809` **before**
  `init_timers()` (819) and `post_init()` (821), and neither is pcall'd. One
  throw leaves the addon "initialised" with no bars, no retry, and event
  handlers now running against half-state. The chained error handler is
  installed first (`816-818`), so `/st diag` would at least show it — but the
  user gets no notice. Class `post_init` is guarded (`978-982`), the engine's
  own init is not.
- `OnInitialize` assumes `self.defaults` (set by `config.lua` at file scope) and
  the five libraries (`LRC/LLM/LGC/LWIN` are non-silent `LibStub` fetches,
  `51-54`). The TOCs guarantee both; a partial copy of the addon errors at load
  before any frame exists. Acceptable.
- `table.pack` is defined globally at `87-89`; `enemy_swing.lua:250-252` has its
  own local `pack` and says so. Fine.

## 4.6 Secret-value / taint / protected APIs

- **HU-23 holds in scope: zero client range/inspect calls.** `grep
  CheckInteractDistance|UnitInRange|IsItemInRange` over the 12 files = comment
  text only (`main.lua:2422, 2428`). The only distance read is
  `api.UnitDistance` → `UnitDistanceSquared` (`compat.lua:1035-1051`).
  `api.IsSpellInRange` (HU-24, open) has **no caller in scope**.
- Secret-value guards are present on every wrapper that touches a restricted
  read (auras 530-570, casts 723-752, cooldowns 307-335, power/health 426-515,
  totems 1296-1314, items 1365-1415). All degrade to the documented "unknown"
  shape.
- Direct, unguarded unit calls: `UnitExists`/`UnitCanAttack` in
  `main.lua:2183-2188`, `hud.lua:745-746`, `enemy_swing.lua:304-322`, and
  `UnitGUID` in `main.lua:537, 1070-1071`. On `live`, neither `UnitExists` nor
  `UnitCanAttack` is `SecretReturns` (`live:…/UnitDocumentation.lua:752-766`,
  `1164-1176`), so no throw today; they are still a cross-client contract
  exception (AGENTS: "never call a cross-client API directly elsewhere").
  `hidden-failure` risk only, no live evidence of a problem.
- Taint: `seterrorhandler` chaining (`diag.lua:556-594`) is chained and removed
  on logout (`1586-1593`); bars/HUD frames are non-secure; HUD defers all
  creation/reflow under `InCombatLockdown` (`687-692, 873-877, 983-986,
  1370-1374, 1399-1402`) — correct.
- **Combat-lockdown frame mutation in bars.lua:** none of the bar setters guard
  lockdown, and `option_tables.lua:124` calls `configure_frame_strata` from an
  option setter, which runs `frame:SetFrameStrata` (`bars.lua:341`) — the
  AGENTS rule says keep strata/parent changes out of combat. Bars are
  non-secure so this is not a protected-call error; LOW (rule adherence).
- `ensure_bar` can create frames during combat via
  `PLAYER_EQUIPMENT_CHANGED` (`main.lua:1574-1583`) — legal for non-secure
  frames, noted for completeness.

## 4.7 Class activation key mismatch (supported option, latent)

`activate_class` records the selected class in `self.active_class`
(`main.lua:755, 791`), but main.lua's dispatch and settings use
`self.player_class` everywhere: CLEU (1098), spellcast (2013), rage (1863),
aura (2835), queue colour (2842), combat exit (1757), post_init (970),
`get_class_table` (244). Consequence of an explicit non-playing pick
(`option_tables.lua:219-248`, default "Auto"): the selected module loads **but
receives none of the class events**, and it reads the *playing* class's profile
row. That is a coherent-looking option with a broken back half. Either route
the dispatch/settings through `active_class` (bigger change, matches the R0
comment) or make the picker explicitly dev-only/`Auto`-locked.

---

# 5. Cross-client feature probes

## 5.1 Probes that run at load (correct)

Family/interface (`compat.lua:49-97`), `issecretvalue` (152), spell-known
probes (204-227), `C_Spell`/`C_Item`/`C_Totem`/`IsSpellInRange` shapes
(307-355, 1326-1343), `GetTimePreciseSec` (1468-1492),
`UnitDistanceSquared` (1033), `C_EventUtils.IsEventValid`
(`main.lua:672-691`, `swing_source.lua:48-64`, `enemy_swing.lua:637-646`,
`hud.lua:617-621`), `PLAYER_SWING` (swing_source 64). All present on every
targeted branch (verified by `git grep` over
`Interface/AddOns/Blizzard_APIDocumentationGenerated` on `classic_era`,
`classic_anniversary`, `classic_titan`, `origin/forever`, `live`).

## 5.2 Probes that run per frame/tick and should be resolved once

1. `api.is_spell_known_state` per HUD spell slot per 0.05 s tick
   (`hud.lua:824-825`) — knowledge changes only on learn/level/respec.
2. `api.GetInventoryItemCooldown` per trinket per layout poll to answer "is this
   item on-use" (`hud.lua:324-330`) — item-static; cache with the item id in
   `HUD.read_trinket` (`276-291`, already keyed on item change).
3. `api.UnitAura` walks per trinket per tick (`303-317`) — one sweep per tick
   would serve both slots.
4. `st.family` compares per aura tick (`1041`) and `st.is_mainline` per
   utility-cast/`SWING_TIMER_START` — cheap string/bool compares, fine.

## 5.3 Branch-specific risks

- **TBC**: `UNIT_AURA` unreliable → the 20 Hz poll is the archive-parity
  choice (`1014-1025`), but it is unconditional (no combat/visibility gate) and
  runs the 40-row paladin scan (§1.4). Any TBC-only perf fix must preserve the
  "seal changes are never missed" contract.
- **TBC**: main.lua's TBC ranged fallback (`2032-2115`) is correct in shape
  (it never double-drives a live engine) but does one wasted
  `api.GetSpellInfo(75)` **per non-Auto-Shot player cast** (`2047-2049`) — the
  code's own comment at `2026-2029` says payloads carry numeric ids on every
  family, so the name comparison is dead weight.
- **Era/Wrath**: no aura poll; `UNIT_AURA` event only. `START_AUTOREPEAT`
  validity-probed; all fine.
- **Forever** (`_Mainline` toc): engine = `swing_source` (`swing_source.lua`),
  `CLEU` not registered (`main.lua:710`), enemy_swing inert
  (`enemy_swing.lua:644`), HUD works. The per-swing `C_Timer.After`
  (`swing_source.lua:226`) is the only timer churn there.
  Observation (cross-client lane owns the file): the new
  `on_weapon_slot_changed` restart (`swing_source.lua:319-326`) was still
  leaving `cycle.start` stale while `SwingTimerInfo` reports it
  (`swing_source.lua:396-404`) — a caller seeding from `SwingTimerInfo` (init or
  the late-INFO rewire, `main.lua:471-487`) would have taken a stale start after
  a swap. **That lane landed `cycle.start = t` at `swing_source.lua:325` during
  this audit; verified fixed at md5 450cff58.** No action for this desk.
- **Retail**: no swing engine (`main.lua:42-44`, inert stand-in), CLEU not
  registered, `PLAYER_TARGET_SET_ATTACKING` gated. The range poll, HUD driver
  and `enemy_swing`-inert paths still run; Retail pays the same idle cost as
  Era minus the swing work.

---

# 6. Idle cost — is the off path really off?

| state | bar tick | range poll | aura poll | HUD | enemy |
|---|---|---|---|---|---|
| no target, out of combat, bars hidden | **off** (hidden frame, wiki) | **on 20 Hz** + visibility pass + alpha | TBC: **on** | **on** (driver frame never hidden) | CLEU listener **on** + per-event LibStub lookup |
| bars disabled in settings | off (never built, HU-22) | **on** (disabled branch still hides 20×/s per hand) | TBC: **on** | **on** | as above |
| practice off | unchanged | on | on | on | on |
| options closed | unchanged | on | on | on | on |
| `st.debug=false` | — | — | — | — | — |
| diag tick counters off | — | — | — | — | `diag.wrap_onupdate` returns the **original** function object (`diag.lua:282-284`) — genuinely zero overhead |
| no broker installed | — | — | — | — | `ldb.update` → `ldb.init` latches `init_attempted` (`ldb.lua:152-155`) and returns; one call/frame |
| no zones registered | — | — | — | — | one table read (`bars.lua:912`) |

**Proven off:** bar ticks on hidden frames (engine-blocked, wiki citation),
class hook when no class module (nil check), zones when unused, diag counters
when off, LDB after the one failed attempt.
**Not off, and should be:** range poll (main.lua), HUD driver + layout poll
(hud.lua), enemy-swing CLEU listener (enemy_swing.lua), TBC aura poll —
four always-on paths for features that may be disabled or invisible.

---

# 7. Top 10 optimizations (ranked value / effort)

Effort: S = <1 h, M = half-day + pins, L = structural. "Effect" is derived from
the counts in §1; no in-client profile exists yet (see §10).

### O1. Cache the bar texts, and pass the tick's clock into `set_bar_texts` — **value high / effort S**
`bars.lua:1219-1282`, called from `900`.
The tick already has `t` (`762`); `set_bar_texts` reads the clock again
(`1219`) and rebuilds `lookup` + 2 `string.format` + 3 `SetText` every frame
while the displayed tenth changes ~10×/s.
Sketch: `set_bar_texts(hand, t)`; build `attack_speed`/`swing_timer` only when
the quantised value differs from a per-frame `_text_cache` (per hand, per
slot); call `SetText` only on change. Kills ~60 tables, ~120 strings, ~180
`SetText`/s per hand. Suite check: `tests/bars_state.lua:1163-1315` asserts
text *values*, not call counts — stays green.

### O2. Make the spark a configured decoration, not per-frame math — **value high / effort S**
`bars.lua:804-818`.
`spark:SetSize`, `ClearAllPoints`, `SetPoint("CENTER", frame.bar, "RIGHT")`,
`convert_color(db.spark_color)` and `SetVertexColor` produce the same result
every frame; the anchor follows the bar's width on its own. Only `Show`/`Hide`
depend on progress, and only on the 0/1 transitions.
Sketch: set size, colour and anchor once in `configure_bar_appearances`
(`346-366`) / a new `configure_spark`; per tick keep
`if progress > 0 and progress < 1 then Show else Hide`. Removes ~5 C calls and
a 4-division conversion per tick per hand (≈ 300 C calls/s/hand).

### O3. HUD: stop polling layout at frame rate, and cache "is this trinket on-use" — **value high / effort S**
`hud.lua:697-715` (per-frame poll), `1056-1079`, `324-350`, `763`.
Sketch: (a) `HUD.on_bar_update` keeps only the `ensure_created` retry and the
`pending_apply` check; the 20 Hz driver already owns layout polling (option
setters call `apply_settings` directly — `option_tables.lua:537-625`); (b) add
`t.has_on_use = trinket_has_on_use(slot)` inside `read_trinket` (item changes
are already detected there) and read it in `trinket_usable`. Removes
~60-120 layout polls/s and 120-240 inventory C calls/s per class, while hidden.

### O4. HUD: one aura sweep per tick, and latch spell-known — **value high / effort M**
`hud.lua:303-317` (2 walks/tick), `391`, `816-839`, `1306-1307`.
Sketch: one `scan_player_auras()` per `update_display` returning a small reused
map/two stamps (proc expires for slot 13/14 + the seal/AoW rows the class
provider needs), or at minimum pass one scan result to both trinkets. For
spell-known: cache `{query → known,state}` per slot, invalidate on
`SPELLS_CHANGED` / `PLAYER_LEVEL_UP` / `PLAYER_ENTERING_WORLD` and keep the
fail-visible rule (`state == "unknown"` ⇒ show). Removes ~500 client calls/s
on a paladin and ~800/spell-known probes.
Suite: `tests/hud_state.lua` pins the provider exactly-once contract — the
scan cache must not re-enter providers.

### O5. Replace both `C_Timer.After` re-arm chains with `C_Timer.NewTicker` — **value high / effort M**
`main.lua:1028-1051` (aura), `2501-2531` (range).
Sketch: one ticker per poll, created at init, callback = today's body; keep the
retry backoff by cancelling + re-creating only in the failure branch. Removes
40 timer objects + 40 closures per second on TBC (20 elsewhere).
Pins to re-cut (file, do not edit): `tests/main_init_state.lua:1393-1470`
(§11a/11b count `C_Timer.After` timers at 0.05), `tests/range_source_state.lua`
(captures `after`). Value also includes making the loop unkillable (§R1).

### O6. Run the visibility/alpha pass only when one of its inputs changed — **value high / effort M**
`main.lua:2529-2530`, `2660-2682`, `2537-2567`.
Sketch: compute a small key `{in_combat, has_attackable_target, in_melee_range,
in_ranged_range, class_enabled, practice_active, per-hand enabled/show_behaviour/
require_in_range}` in `update_range_state` and call the pass only when it
differs from the last key; keep explicit calls from combat/target/option/practice
transitions. Drops ~2,400-4,200 Lua ops/s + 120-240 C calls/s at idle to near
zero, and removes the 20 Hz `SetAlpha`/`Show`/`Hide` churn.
This is the same edit that fixes §R1 if the pass is moved behind a
dirty-flag + always-armed driver.

### O7. Unit-scope the 11 player-only unit events — **value high in raids / effort M**
`main.lua:695, 699, 713-725`.
Sketch: one private frame created in `OnInitialize` (not AceEvent's shared
frame) with `RegisterUnitEvent` for `UNIT_AURA`, `UNIT_POWER_FREQUENT`,
`UNIT_TARGET`, and the 7 player-only `UNIT_SPELLCAST_*`; register
`UNIT_SPELLCAST_START` with `"player","target"` (the pull clock needs target);
`SetScript("OnEvent", function(_, event, ...) ST[event](ST, event, ...) end)`.
Remove those names from the AceEvent registrations. Drops every other unit's
aura/power/cast/target dispatch in a raid. Cite:
`classic_era:…/SimpleFrameAPIDocumentation.lua:943` and Blizzard's own two-unit
use `classic_era:…/Blizzard_BuffFrame/BuffFrame.lua:285`.

### O8. CLEU: cache the target GUID; gate the two extra listeners — **value high in raids / effort S-M**
`main.lua:1071` (one `UnitGUID("target")` per CLEU event);
`enemy_swing.lua:586-592` (LibStub lookup per event while off);
`hud.lua:609-644` (a third listener whenever trinkets exist).
Sketch: register `PLAYER_TARGET_CHANGED` once and cache
`self.target_guid`, refreshed also on `PLAYER_ENTERING_WORLD`/`UNIT_TARGET
("player")`; in enemy_swing cache `local owner` after the first successful
`get_addon()` and keep a module-level `enabled` flag written by the option
setter (or register/unregister CLEU on toggle); in HUD gate the listener on
`any equipped trinket has an icd` and unregister when it changes.
Removes 300-1,000 C calls/s and ~5,000-20,000 Lua ops/s in a raid, most of it
for a disabled feature.

### O9. Remove per-event allocations in the swing dispatcher — **value medium / effort S**
`main.lua:1183-1207`, `1312-1331`.
Sketch: replace `event:sub(1,12) == "SWING_TIMER_"` with a precomputed
`SWING_EVENTS[event]` set (or `event:byte(1) == 83` + length check); replace
`local args = {...}; unpack(args, 2, n)` with
`pcall(handler, ST, event, select(2, ...))`; make `swing_wire_last` a single
reused table (`last.hand/kind/t = ...`) and read the clock only for the age
line. Zero behaviour change; −2 allocs/event.

### O10. Compat: one-time branch for the no-secret regime; drop the dead GCD key — **value medium / effort S-M**
`compat.lua:152-154` + hot wrappers (`530-570` aura, `727-752` cast,
`1035-1051` distance); `main.lua:1272-1284`.
Sketch: `local have_secrets = issecretvalue ~= nil` and select the
guarded vs pass-through wrapper at load (classic clients get the raw path);
today every aura row pays 10 `is_secret()` Lua calls that can only ever return
false. And `get_gcd_time_before_swing_seconds` builds
`"gcd1_spell_time_before_swing_" .. tostring(hand)` on **every paladin bar
tick** (caller `classes/paladin.lua:3444`) to read a key **nothing writes**
(`grep` = this line only) — delete the dead branch and return the precomputed
field.

### Also worth doing (not in the ten)
`PLAYER_ENTERING_WORLD` dead registration (`main.lua:656, 1562-1566`);
`/test1` dead command (`2783, 2786-2787`); hunter-only events registered for
all classes (`668-670, 679-680`); `api.GetSpellInfo(75)` per non-Auto-Shot cast
(`2047-2049`); lazy build of `swing_reset_names` on the first player cast
(`1920-1928`, 13 `pcall(GetSpellInfo)` at the pull); `ldb.update` reads the
clock before its own throttle (`ldb.lua:208-213`) — pass the tick's `t`.

---

# 8. Top 5 reliability fixes (ranked severity)

### R1 — HIGH — bars stop showing/hiding when the range poll dies
`main.lua:2501-2532` (return sites `2502-2505`, `2514-2518`; unprotected
`2529-2530`; re-arm only at `2531`).
Scenario: the designed M1 dead-man (3 distance-probe throws) disables range
checking and returns before the visibility pass; or any throw in
`set_bar_visibilities`/`handle_oor` escapes the `C_Timer` callback. Either way
no bar is shown or hidden again for the session (bars freeze visible or
invisible), with no notice beyond the range line.
Evidence that it is reachable: `tests/main_init_state.lua:1269-1338` drives
`rf_update` into `rf_disabled` and asserts no throw — the dead-man is a
supported state, and the visibility call is after the return.
Fix: arm the poll with a `C_Timer.NewTicker` created once (survives any body
error), move `set_bar_visibilities()`/`handle_oor()` inside the `pcall` (or
their own pcall) and drive visibility from the dirty-flag of O6; optionally
retry range once after a cool-down instead of latching forever.
Pins: `tests/range_source_state.lua`, `tests/main_init_state.lua` §10/§11.

### R2 — HIGH — stale extra-attack suppression eats the next pull's first swing
`main.lua:1400-1415`, `1467-1480`, `1749-1761`; no reset anywhere (`grep`).
Scenario: pending extra attack at combat exit → STOP arms the hand
(`1473-1476`) → next fight's first START is swallowed (`1401-1408`) and its
STOP too (`1478-1480`); one dead cycle on the pull. The paladin resets its
analogous counter on combat exit (`classes/paladin.lua:2214-2218`), which is
the proof this is an omission, not a design.
Fix: clear `extra_attack_pending`, `suppress_armed`, `suppress_next_stop` in
`PLAYER_REGEN_ENABLED` (and stamp the arm with a time, expiring after ~2×speed).
Pin: extend the in-fight suppression block `tests/real_wire_state.lua:1763-1832`
with a combat-boundary leg (file the pin; that suite has an owner).

### R3 — MEDIUM — the class picker's back half is disconnected
`main.lua:755, 791` (`active_class`) vs `970, 1098, 1757, 1863, 2013, 2835,
2842` (`player_class`) and `get_class_table` (`244`).
Scenario: an explicit non-playing pick loads that module but it never receives
CLEU/spellcast/aura/rage events and reads the playing class's settings row, so
the selected class can look "loaded but dead". Default "Auto" hides it.
Fix: pick one key. Route the dispatch/settings through `active_class` (and keep
`player_class` for hands/class facts), or mark the picker dev-only.

### R4 — MEDIUM — `interfaces_are_initialised` latches before the risky half of init
`main.lua:809-821`; nothing pcall'd between the latch and `post_init`.
Scenario: a throw in `init_timers`/`post_init` leaves the addon flagged
initialised with no bars, no retry, and the class/UI hooks now running against
partial state; only `/st diag` (error ring, installed at `816-818`) shows it.
Fix: wrap each step in `st.guard.run` (`init:timers`, `init:post`) and announce
the first failure, or set the flag only after both succeed and retry once.

### R5 — LOW — timer-handle hygiene on the bar-full timer
`main.lua:1498-1507`: a new STOP overwrites `bar.is_full_timer` without
cancelling the previous timer; the orphan fires later and runs
`live.is_full = true; on_bar_inactive(hand)` at the wrong time (the bar reads
"full/inactive" mid-swing). `restart_swing_for_reset` cancels but leaves the
stale handle in place (`1954-1958`). Trigger is unproven (needs two STOPs
without an intervening START); the code fact is certain.
Fix: `if type(bar.is_full_timer) == "table" and bar.is_full_timer.Cancel then
bar.is_full_timer:Cancel() end` before overwriting; nil the field in
`restart_swing_for_reset`; keep the existing guard shape.

**Known residual, already disclosed 2026-10-22 (not re-filed):**
`SWING_TIMER_START` cancels `bar.is_full_timer` unguarded (`main.lua:1426-1427`)
while `restart_swing_for_reset` pcall-guards the same operation.

---

# 9. Ten enhancements (ranked), at least three confusion-reducers

1. **`/st why` — print the visibility decision per hand.** `class_enabled`,
   hand `enabled`, spec flags, weapon probe, `show_behaviour`/`show_condition`,
   `require_in_range`, range state, practice override, built/unbuilt, and the
   final show/hide. *Why: the addon's recurring failure is "bar invisible" with
   no explanation; every gate already exists as a readable field. Effort: S-M.*
   **(confusion)**
2. **Login line gets a per-hand gate summary.** Extend `diag.config_line`
   (`diag.lua:326-338`) with `hands=mh:on,oh:no-weapon,ranged:on` and the
   reason a configured hand was not built. *Why: turns "it didn't load" into a
   named fact at the exact moment the user looks. Effort: S.* **(confusion)**
3. **Range text: distinguish "unknown" from "no target".** `bars.lua:1236-1244`
   renders `""` for both; `update_range_state` sets nil on an unreadable
   distance (`main.lua:2468-2473`). Render `?` when a target exists but the
   client cannot measure, vs blank when there is no target. *Why: an empty
   field currently reads as "0 yards". Effort: S.* **(confusion)**
4. **`/st perf [seconds]` — session-scoped tick counters.** Today
   `diag.wrap_onupdate` needs `db.profile.diag_tick_counters = true` and a
   reload (`diag.lua:278-311`, `config.lua:30`). Make a command install the
   wrapper for the session and print ticks/CPU per hand after N seconds.
   *Why: the instrumentation exists and is unreachable in practice; this is how
   you validate O1-O6 in-client. Effort: S-M.*
5. **Strip the `[n]` debug counter from user-facing chat.**
   `utils.lua:6-18` prefixes every `print_msg` with `st.debug_counter`. Keep it
   when `st.debug`, drop it otherwise. *Why: user-facing notices (range
   unavailable, HUD CLEU failure, Forever feed notice) currently look like
   debug spam. Effort: S.* **(confusion)**
6. **"Reset this hand" and "reset layout" in options.** One button per hand
   restoring `ST.bar_defaults` + the class override, one for positions
   (LWIN). *Why: a bar dragged off-screen or a bad texture/alpha combination is
   currently unrecoverable without editing SavedVariables. Effort: S-M.*
7. **Show "default" vs "off" for nil-safe toggles.** Options getters that read
   `~= false` cannot express "unset"; add a muted "(default)" suffix when the
   key is nil. *Why: users cannot tell a deliberate off from an unset default
   — the exact ambiguity `bench/lessons.md` records for `hud_show_*`.
   Effort: S-M.* **(confusion)**
8. **One shared 20 Hz scheduler.** A single ticker (or one never-hidden driver)
   fanning out to range, TBC aura, HUD paint and `weave_range`, replacing four
   independent always-on drivers (`main.lua:2531`, `main.lua:1050`,
   `hud.lua:655`, `weave_range.lua:184`, `rotationtext.lua:563`). *Why: one
   cadence to reason about, one place to pause when nothing is visible.
   Effort: L.*
9. **HUD liveness from events, not polling.** `SPELLS_CHANGED`,
   `PLAYER_EQUIPMENT_CHANGED`, `UNIT_AURA(player)` and the class provider can
   invalidate a small dirty set; the 20 Hz tick then only paints what changed.
   *Why: removes the two aura walks and the spell-known probes (O4) without
   changing what the user sees. Effort: M-L.*
10. **Enemy-swing: register on demand.** Create the driver frame on first
    enable, unregister CLEU when off, and re-read the target when the toggle
    flips on (`enemy_swing.lua:644-676`, `524-532`). *Why: a default-off
    feature should cost zero; also fixes "turn it on mid-fight and nothing
    shows until the target changes". Effort: S-M.*

---

# 10. UNVERIFIED / missing knowledge

- **No in-client measurement.** Every per-second figure in §1 is derived from
  call counts in the code, not profiled. The addon already has the tool
  (`diag.wrap_onupdate`), and O3/enhancement 4 would make it usable; a real
  session on classic_anniversary would close this.
- **C-side early-outs** (`Show()` on a shown frame, `SetText` with identical
  text) are engine internals; the claimed win is the removed Lua chain and
  allocations, not the C call itself.
- **Raid event rates** (`UNIT_AURA`, `UNIT_POWER_FREQUENT`, CLEU per second) are
  environment-dependent; the finding is the *path cost per event*, not a
  measured rate.
- **The 2-unit cap of `RegisterUnitEvent`** is engine behaviour; I verified
  two-unit usage in Blizzard code (`classic_era:…/BuffFrame.lua:285`), not the
  documented maximum.
- **R2's trigger**: I verified (a) `SwingEnd` fires STOP at every cycle end
  (`Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:204`), (b) no
  combat-exit reset exists in main.lua or any class, (c) the paladin resets its
  own counter for the same reason. Whether the vendored lib emits STOP on
  target death specifically is UNVERIFIED (no `UNIT_DIED` handler found in the
  lib); the verified trigger is "pending extra at any STOP that is not followed
  by that extra's START before combat ends".
- **`compat`'s `0,0` fallbacks** for `UnitAttackSpeed` are only reachable on a
  client without those globals; none of the five targeted branches lacks them
  (verified in the API docs), so the exposure is private/unknown clients.
- Out-of-scope files were read only to follow a call chain
  (`classes/paladin.lua` parse_seals/process_aow, `classes/hunter.lua` hand
  gate, `option_tables.lua` setters). Findings inside those files belong to
  `audit-features` / the owning lanes: the 40-row unconditional aura walk
  (`classes/paladin.lua:590-600`) and the 2-frame-rate HUD hook
  (`classes/hunter.lua:1026`) are the two that matter to the numbers above.

---

# 11. Verified clean (no change)

- Clock purity: zero raw `GetTime`/`GetTimePreciseSec` in shipped core outside
  `compat.lua:1468-1492` (and `swing_source.lua:74-79`'s documented no-api
  fallback).
- Protected calls: none in scope (HU-23 held); `api.IsSpellInRange` (HU-24) has
  no caller here.
- Event names: all 30 registrations exist on `live` except the correctly gated
  `PLAYER_TARGET_SET_ATTACKING`.
- Guard contract: counting + once-per-site + 25-throw quarantine
  (`guard.lua:112-179`); `diag` counters off = zero overhead.
- Diag: print-only, capped (`MAX_LINES=85`, `ERROR_MAX=8`), pcall-per-line,
  never throws.
- Hidden-frame ticks: bar and enemy-swing stop (wiki), proving the "off path" is
  off for those two.
- HU-22 lazy bars: every per-hand consumer is `bar_is_built`-gated; the
  disabled branch hides rather than throwing.
- HUD combat lockdown: creation, apply and reflow all defer correctly.
- LDB: one object per session, 4 Hz publish, change-gated writes
  (`ldb.lua:197-249`).
- No unbounded growth in scope (§3).
