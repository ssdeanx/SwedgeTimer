# Bar perf fix — mechanical wins + verified rounding fix (2026-11-06)

Desk `bars-perf-fix` (writer: `bars.lua`, `utils.lua`, `tests/bars_state.lua` only).
Operator report addressed: "the swing bars take a lot of resources and are a little buggy
on WoW Forever." This pass implements the safe mechanical wins from the current-tree perf
audit — no layout, no config, no visible-behaviour change beyond the verified rounding bug.

**Input warning.** The dispatch cited `bench/bars_perf_audit_2026-11-06.md` §2/§3/§8
A1/A2/A3/§9.1. That file on disk is a **17-line stub** written by a rogue read-only desk
(Lead-confirmed; it also wrongly bumped version fields to 2.2.0, which this desk did NOT
touch). The audit sections were not readable; this pass used the dispatch's A1–A4
specification plus the audit desk's own journal (`desks/perf-audit/journal.md`, which
records the same census and the `simple_round` proof). Nothing here relies on the stub.

## Files changed

| File | Change |
|---|---|
| `bars.lua` | A1 (tick clock into `set_bar_texts`), A2 (spark decoration cache), A3 (single fill write at the end of the tick) |
| `utils.lua` | A4 (`simple_round` nearest-tenth with half-up epsilon) |
| `tests/bars_state.lua` | new §2a pins (clock read count, spark deco-call count/live-db reapply, single fill write, 8 truncated speeds + half case); stub call counters; one stale pre-existing pin corrected (1.95 s: `1.9` → `2.0`) |
| `bench/bars_perf_fix_2026-11-06.md` | this report (new file) |
| `desks/bars-perf-fix/**` | desk journal + done signal |

No TOCs, no version fields, no README/CHANGELOG, no `tests/run.sh`, no git commands.
LF endings preserved on all three files (0 CR lines each; re-checked with `file`/`grep`).
`luacheck bars.lua utils.lua tests/bars_state.lua` → **0 warnings / 0 errors**; `luac5.1 -p`
clean.

## A1 — the tick's clock instead of a second read

`st.api.get_time()` = `GetTimePreciseSec()` + `GetTime()` = **2 C calls** on every client
that has the precise clock (`compat.lua:1739-1754`). `onupdate_common` already reads it at
`bars.lua:1141` (`t`); `set_bar_texts` read it again at `bars.lua:1657`.

```lua
-- bars.lua 1629
function ST:set_bar_texts(hand, now)
...
    -- bars.lua 1654-1660
    -- The caller's clock when it has one (the tick reads it once at the top), else read it
    -- here. api.get_time() is two C calls on every client with GetTimePreciseSec (the
    -- precise read plus the GetTime() domain reference), so a per-tick caller hands its
    -- own reading through instead of paying for a second pair.
    local t = now
    if type(t) ~= "number" then
        t = st.api.get_time()
    end
```

All three tick call sites now pass the tick clock: the normal paint (`bars.lua:1294`),
the engine-dead early return (`bars.lua:1152`) and the no-cycle early return
(`bars.lua:1166`). Non-tick callers (`ensure_bar` `bars.lua:231`, `on_attack_speed_change`
`bars.lua:1391`) keep the no-argument form and read the clock once, exactly as before.
No other module changed.

## A2 — the spark is a configured decoration

Before (`bars.lua:1181-1196` old): every shown frame did `SetSize` + `ClearAllPoints` +
`SetPoint` + `convert_color` + `SetVertexColor` + `Show()` — 5 client calls, although only
`show_spark` / `spark_width` / `spark_color` / bar height change the look.

After (`bars.lua:1181-1234`): a per-hand cache key (`spark_deco_*` on the hand state)
compares width, height and the four raw colour components against the live db on **every**
tick; the geometry/colour block runs only when the key changes. Per tick the spark does
only `Show()` (conditions met) or `Hide()` (conditions not met). Turning `show_spark` off
invalidates the cache so re-enabling repaints once. Exact vertex values are unchanged
(255,255,255,1 → 1,1,1,1; other colours still `convert_color`d). `convert_color` now runs
only on a key change — it never had a visible side effect.

## A3 — one fill write per tick (restructure variant)

Before (`bars.lua:1175-1178` old): the fill pair `SetWidth` + `SetTexCoord` was written at
the top of the tick **and again** as the final re-assert (`bars.lua:1319-1322` old, the
2026-10-28 hunter correctness fix). The top write could only ever be overwritten later in
the same tick (by `configure_bar_size_and_positions` and by the final write), so it was
pure duplicate work.

After: the top write is deleted; the tick's **single** fill write is the final block
(`bars.lua:1341-1362`), which is structurally the last statement of `onupdate_common`.
This is the dispatch's explicitly permitted "restructure so the tick writes once at the
end and the resize path still repaints" variant: it needs **no dirty-flag bookkeeping**
and keeps the correctness contract, so `tests/bars_state.lua` 12c2 (fill survives a
resize) and 12c3 (fill is the tick's last word) were **not modified** and stay green.
The resize path (`configure_bar_size_and_positions`, `bars.lua:664-687`) still repaints
the live progress itself (2026-10-28 fix untouched).

## A4 — verified rounding bug (`st.utils.simple_round`)

`utils.lua:22-24` old did `floor(num/step)*step`, i.e. truncation. Because one-decimal
numbers are not exact multiples of 0.1 in binary floating point, the quotient sits a hair
below the integer and a whole tenth was dropped: **8 of the 28 one-decimal weapon speeds**
displayed a tenth low — 1.4→"1.3", 1.9→"1.8", 2.3, 2.4, 2.8→"2.7", 2.9, 3.3, 3.8. It is
used only by the bar attack-speed/timer texts (`bars.lua:1666` / `:1672`); the archived
build has the same line (inherited, not a regression).

```lua
-- utils.lua 34-36 (WHY comment above it)
st.utils.simple_round = function(num, step)
    return floor(num / step + 0.5 + 1e-9) * step
end
```

`floor` remains the client's global (Blizzard `Compat.lua` sets `floor = math.floor`;
the offline harness sets `env.floor`) — deliberately NOT localized to `math.floor`.
The `1e-9` is the dispatch's tiny epsilon: it stops a true half case from rounding down
because of representation error (1.95 s → 2.0, not 1.9; 0.35 → 0.4). One visible
consequence (intended, and pinned): the swing timer now shows **"2.0"** where it used to
show "1.9" at 1.95 s remaining; the pre-existing pin at `tests/bars_state.lua` §2 was
corrected from `1.9` to `2.0` with the reason in a comment.

## Per-tick client-call counts (derived from source, NOT in-client profiled)

Per hand, per normal tick:

| Item | Before | After | Saved |
|---|---|---|---|
| A1 clock (`api.get_time` = 2 C calls) | 2 reads = **4 C calls** | 1 read = **2 C calls** | **2 C calls** |
| A2 spark (shown during a swing) | 5 calls (`SetSize`, `ClearAllPoints`, `SetPoint`, `SetVertexColor`, `Show`) | 1 call (`Show`) | **4 C calls** |
| A2 spark (hidden: full/idle/option off) | 1 (`Hide`) | 1 (`Hide`) | 0 |
| A3 fill | 2 pairs = **4 C calls** (2×`SetWidth`, 2×`SetTexCoord`) | 1 pair = **2 C calls** | **2 C calls** |
| **Total, spark shown** | **13 C calls** | **5 C calls** | **8 C calls/tick/hand** |
| **Total, spark hidden** | **9 C calls** | **5 C calls** | **4 C calls/tick/hand** |

Arithmetic projection only (not measured): at 60 FPS with three built hands that is
up to 24 saved C calls/frame (1,440/s) while all three sparks are live, 12/frame (720/s)
when idle. The mainhand LibDataBroker feed's own `api.get_time()` (`ldb.lua:208`) is
unchanged and outside this scope. Early-return paths (engine dead / no cycle) still write
their one fill sliver and now use the same single clock read.

## Red-first evidence

Baseline before the work: `lua5.1 tests/bars_state.lua` → **1261 checks, PASS**.
The new §2a pins were added first (44 new checks → 1305). Against the unfixed tree the
suite went **20 of 1305 failed** — exactly the intended pins, nothing else:

```
FAIL  quarter swing: swing timer rounds to nearest tenth  (got 1.9, want 2.0)
FAIL  round: 1.4 displays its own tenth (was truncated)   (got 1.3, want 1.4)
... 1.9/2.3/2.4/2.8/2.9/3.3/3.8 the same shape (8 speed pins)
FAIL  round: a 1.95 s remaining rounds half up to 2.0     (got 1.9, want 2.0)
FAIL  tick clock: the offhand tick reads the clock exactly once        (got 2, want 1)
FAIL  tick clock: the no-cycle early-return paint also reads the clock once (got 2, want 1)
FAIL  text clock: set_bar_texts uses the clock it is given             (got 0.0, want 1.0)
FAIL  text clock: set_bar_texts does not re-read the clock when handed one (got 1, want 0)
FAIL  spark: an unchanged key applies no decoration calls              (got 8, want 4)
FAIL  spark: the next tick applies no decoration calls either          (got 12, want 4)
FAIL  fill: exactly one SetWidth per tick                              (got 2, want 1)
FAIL  fill: exactly one SetTexCoord per tick                           (got 2, want 1)
FAIL  fill: still one SetWidth per tick after an out-of-band resize pass  (got 2, want 1)
FAIL  fill: still one SetTexCoord per tick after an out-of-band resize pass (got 2, want 1)
```

After the four fixes: `lua5.1 tests/bars_state.lua` → **PASS, 1305 checks** (green).

How the pins bite (and why they are not vacuous):

- A1 tick-count pins use the **offhand** tick: the broker feed is mainhand-only and the
  warrior class hook returns for the offhand, so every clock read in that tick belongs to
  the code under test; the fixture now counts `GetTime`/`GetTimePreciseSec` calls.
- A1 value pin: the tick at `sb.clock = 11.58` with `ends_at = 12.6` must show **"1.0"**;
  a stale/zero clock would show "12.6". A direct `set_bar_texts("offhand", 11.6)` call must
  show "1.0" while the live clock is 12.5, and must not read the clock at all.
- A2 pins count the spark texture's own `SetSize`/`ClearAllPoints`/`SetPoint`/`SetVertexColor`
  calls: 4 on the first shown frame, **0** on later frames with an unchanged key, and
  >0 again after a live `spark_width`, `spark_color` or bar-height change (no setter hook).
  Geometry/colour values are still asserted exactly, so the visual is pinned too.
- A3 pins count the fill texture's `SetWidth`/`SetTexCoord` calls across one tick: exactly
  one each, including after an out-of-band resize pass, and the single write must equal the
  live progress.

## Mutation proofs (isolated `/tmp` copies, sources only — no Media/docs/.git)

Each mutation was applied to a fresh `rsync` copy of the current tree and run against the
same suite; the numbers are the failures the mutation produced.

| # | Mutation | Result |
|---|---|---|
| M1 | `simple_round` reverted to `floor(num/step)*step` | **10 of 1305 failed**: all 8 truncated-speed pins, the corrected 1.95 s pin, the half-up pin. Kills A4. |
| M2 | spark cache defeated (`deco_dirty = true or …`, i.e. the old per-frame rebuild) | **2 of 1305 failed**: "an unchanged key applies no decoration calls" (got 8, want 4) and "the next tick applies no decoration calls either" (got 12, want 4). Kills A2. |
| M3 | top-of-tick fill write re-inserted (the duplicate A3 removes) | **4 of 1305 failed**: all four single-fill-write pins; **12c2 and 12c3 stayed green** (no other failure). Kills A3. |
| M4 | the tick hands `set_bar_texts` a stale/zero clock (`(hand, 0)`) | **4 of 1305 failed**, including "tick clock: the timer is 12.6 - 11.58 = 1.0 s (got 12.6, want 1.0)" and the timer-value pins. Kills A1's value contract. |
| M4b | A1 reverted inside `set_bar_texts` (unconditional `st.api.get_time()`) | **4 of 1305 failed**: both tick clock-count pins (got 2, want 1), the explicit-clock value pin (got 0.1) and the no-re-read pin (got 1, want 0). Kills A1's optimisation. |

Note on M3 wording: the dispatch's M3 assumed the dirty-flag variant. A3 was implemented
as the dispatch's explicitly permitted restructure variant (one write at the end, no flag),
so the equivalent non-vacuous mutation is re-introducing the duplicate write — which is
exactly the regression the pin exists for.

## Harness / crossfire

- At this desk's green point: `lua5.1 tests/bars_state.lua` → **1305 checks, 0 failed**.
- `bash tests/run.sh` was run three times during the wave and reported **57 steps with
  1, then 2, then 3 failed** — all from concurrently-edited files outside this desk's
  scope (see below). Final run before hand-off (14:38): **57 steps, 2 failed**
  (`tests/engine_matrix_state.lua`, `tests/wiring_check.lua`).
  - `tests/engine_matrix_state.lua` — "forever payload: a zero/non-numeric duration is
    ignored" (`swing_source.lua` was being written during the wave; that suite loads
    `compat.lua`, `swing_source.lua`, `main.lua` only),
  - `tests/main_init_state.lua`, `tests/hunter_state.lua` failed in earlier runs and
    passed by the final run — display-fix's `main.lua` / `classes/hunter.lua` mid-write
    (their failure text named main.lua's swing guards),
  - `tests/wiring_check.lua` — exact failures are all main.lua: "main.lua:1635 [accepted]
    ST:SWING_TIMER_STOP( -> on_attack_speed_change, on_bar_inactive reaches bar visuals
    with no interfaces_are_initialised guard" plus "stale ACCEPTED entry:
    main.lua|swing_timer_start-no-guard" and "...swing_timer_update-no-guard", i.e.
    display-fix's main.lua guard changes under the accepted-defect ledger.
  - `tests/swing_source_state.lua` failed once mid-write and passed standalone minutes
    later (`0 FAIL`).
  Evidence this is not this desk: none of those suites load `bars.lua`; the two that load
  `utils.lua` never call `simple_round` (the only function changed there); `engine_matrix`
  does not load `utils.lua` at all. The failure count also changed between consecutive
  runs. **The Lead must re-run the harness after display-fix/powerbar-fix land; this desk
  cannot certify a full-tree green while other writers are active.**
- `luacheck` on the changed files: 0 warnings / 0 errors. Full-tree luacheck in the same
  run: 2 warnings / 0 errors in 100 files (the standing floor).

## UNVERIFIED

- **No in-client profiling.** All counts are derived from source and from the fixture's
  call counters at a scripted 60 FPS-equivalent assumption; no Forever client was run.
  Real per-frame totals, actual OnUpdate rate, hidden-bar behaviour and the two-C-call
  cost of `api.get_time()` on 1.60.1 are stated from compat/main source, not measured.
- **Visual identity** is verified structurally (the same width/texcoord/point/colour
  values are written, just less often) and by the existing pixel-level pins; no in-client
  visual check was possible from this desk.
- The **theme-preset path** (`option_tables.lua:1588`) was not driven; the live-db pins
  prove a plain db write is picked up on the next tick, which is the same mechanism.
- Whether any **third-party/Blizzard code** reads the fill texture's width between the
  (removed) top write and the end-of-tick write: no addon module reads it (grep: only
  `weave_range.lua:339` reads its own bar), but this cannot be observed in-client here.
- **Hidden-but-built hands** still run their OnUpdate per the audit; this pass reduces
  their cost (clock + fill, spark already hidden) but does not gate the tick.

## Follow-ups NOT done (deltas deliberately left for their owners)

- **HUD / Next Action Guide** per-frame consumers (`hud.on_bar_update`,
  `nextaction_ui.on_bar_update` driven from every class hook) — the audit's dominant
  remaining bar-path cost; other files/lanes.
- **Hunter paths**: `hunter_ui.update_range_helper` unthrottled distance/spell-range
  probes, `apply_melee_stack` re-anchoring — `hunter_ui.lua` is display-fix's scope.
- **`ldb.lua`** mainhand feed re-reads `api.get_time()` per tick; it could accept the tick
  clock the same way (A1's shape), but `ldb.lua` is outside this scope.
- **`update_zones`** (`bars.lua:1111-1113`) reads `api.get_time()` per tick when overlays
  are registered; it could take the tick clock too. Not part of A1/A2/A3, so left as a
  clean follow-up inside bars.lua.
- **Structural** (audit's 5 structural items): throttling the tick, caching
  `get_hand_table`/profile chains, and the Option-C "one tick for three hands" restructure
  were not in the safe mechanical set.
- **Full-tree harness green** must be re-certified by the Lead after the other two fix
  desks land (see crossfire above).
