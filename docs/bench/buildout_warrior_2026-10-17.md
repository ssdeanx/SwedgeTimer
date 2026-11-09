# buildout_warrior — warrior build-out round 1 (finisher pass)

Date: 2026-10-17. Desk: warrior. Brief: `bench/briefs/brief_warrior_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").
Session note: this is the FINISHER pass after the first attempt died mid-flight (rate limit); the partial work in `classes/warrior.lua` + `tests/warrior_state.lua` was inspected first, kept where right, and completed.

## 1. Changes

Writable scope held exactly: `classes/warrior.lua` + `tests/warrior_state.lua`. No other file touched; no git ops; no lint-config changes; no `_` renames; CRLF on `classes/warrior.lua` preserved (`file` reports CRLF after the edits).

### classes/warrior.lua — the one code fix (glow-lifecycle bug)

`ST.WARRIOR.get_hud_state`, the `op` slot branch (W7 readiness-glow fallback). Before: `s.glow = (get_overpower_remaining(stamp, now) ~= nil) or hud_usable_now(slot)` — an armed-but-elapsed proc stamp fell through to the usable probe, so the OP glow stayed on after the window elapsed (the hud_state failure). After:

```lua
local op_remaining = self.WARRIOR.get_overpower_remaining(
    self.warrior_overpower_proc_until, now)
if op_remaining ~= nil then
    s.glow = true
elseif self.warrior_overpower_proc_until == nil then
    s.glow = hud_usable_now(slot)
else
    s.glow = false
end
```

Rule: a live window glows and short-circuits the probe; a stamp that is **set but elapsed is the window's own verdict** (no glow, no probe); the probe fallback only covers a client that **never armed a window** (nil stamp — the Mainline-code path where the classic dodge window cannot exist). Still PROBE-ONLY, never gated on `st.is_mainline` alone. The `hud_usable_now` docblock was updated to state the nil-stamp scope.

The rest of the partial work was kept (it was already right): W1 bank cue (`get_bank_state` + amber edge + "BANK" label + nil-off toggle), W2 composite rage gate (`composite_rage_gate` + `gate_composite_action`, wired into `guide.evaluate`), W3 rampage tiers (`get_rampage_tier` + badge recolour), W7 probe fallback (`hud_usable_now`), Battle Shout capture + badge, HS/Cleave tint and Shield Block bar (pre-existing, untouched).

### tests/warrior_state.lua — two test defects fixed, one pin added (618 → 620 checks)

1. **W3 tier row was self-contradictory.** `get_rampage_tier(5, 0, 0)` expected "amber" ("zero expiry") and `get_rampage_tier(5, 0.0, 0)` expected "red" ("elapsed") — but `0` and `0.0` are the same Lua number, so no code can satisfy both. The elapsed row now uses a genuinely elapsed positive expiry: `get_rampage_tier(5, 4.5, 5) → "red"`. The zero-expiry = amber rule stands (client omitted the expiry = unknown, not maintained).
2. **BS badge toggle-off row never turned the toggle off.** The comment says "The toggle off hides a still-live badge" but the row ticked with the toggle still `true`; added `sb.class_db.show_warrior_battle_shout_badge = false` before the tick.
3. **New W7 lifecycle pins** (mirroring the hud_state binding check inside this suite): a stamp set but elapsed → `glow == false` **and the probe is not consulted** (`usable_calls` unchanged). This makes the lifecycle rule mutation-provable inside the warrior suite.

## 2. W2 composite rage gate — truth table (verify §4.2, BINDING)

`gate_composite_action` post-processes the engine's pick (only a `"bt"` pick is re-judged; WW/other picks and RIDE holds pass untouched). `reserve` = the queued HS cost (or Cleave cost) when one is queued, else 0; a numeric client cost wins, else the documented fallback (BT 30 / WW 25); an unreadable rage or cost degrades to ALLOW.

| rage vs thresholds | queued reserve | ww ready? (remaining ≤ 0) | result |
|---|---|---|---|
| rage ≥ bt_cost + reserve | any | any | `bt` (unchanged) |
| rage < bt_cost + reserve | any | no (nil read or > 0) | `nil` (no prompt) |
| rage < bt_cost + reserve | any | yes, rage ≥ ww_cost + reserve | `ww` |
| rage < bt_cost + reserve | any | yes, rage < ww_cost + reserve | `nil` |
| rage unknown | any | any | `bt` (unknown is not a shortage) |
| bt_cost unknown | any | any | fallback 30 used |
| ww_cost unknown | any | yes | fallback 25 used |
| queued cost unreadable | nil read | any | reserve 0 (degrade to the ungated core) |

Numeric rows pinned by the suite (real engine wrapper rows in the last four): (70, bt 30) → bt; (29, bt 30) → ww; (29, bt 30, ww on CD) → nil; (29, bt 30, hs queued 30) → nil (29 < 60); (57, bt 30, hs queued 30) → ww (55 ≤ 57 < 60); (66, bt cost muted) → bt; (29, bt cost muted) → nil; (200, hs queued) → RIDE (gate untouched); engine rows 70 → bt, 29 → ww, 29 + ww CD → nil.

## 3. Option defaults (standing-rule record for the options pass)

| Key | Shipped this pass? | Default | Semantics |
|---|---|---|---|
| `show_warrior_bank_cue` | no (nil in db) | **nil = OFF** | `== true` shows the W1 BANK cue; reads sit behind the toggle |
| `show_warrior_battle_shout_badge` | no (nil in db) | **nil = OFF** | `== true` shows the BS countdown; capture rides the aura walk regardless |
| `show_warrior_rampage_badge` | yes (`config_presets` = true) | ON | `== false` hides; W3 tier colours are constants, no new option |

The W2 rage gate and the W7 probe fallback are **not toggles**: the gate rides the guide (itself behind `nextaction_enabled`, default OFF); the fallback is probe-only. HS/Cleave tint + Shield Block bar options are pre-existing (shipped true). No default-visible change: an untouched profile draws exactly what it drew before (the two new widgets stay hidden while their keys are nil).

## 4. Evidence

- `lua5.1 tests/warrior_state.lua`: **PASS, 620 checks** (was 618 checks / 2 failures). Covers the W2 predicate + wrapper rows, the W1 state matrix and widget path, the W3 tier matrix and badge recolour, the W7 probe matrix (live / elapsed / nil-stamp / false / unknown / no-probe / execute scope), the BS capture + badge matrix, and the pre-existing tracker suites.
- `lua5.1 tests/hud_state.lua`: **PASS, 401 checks** (was 400/401; "warrior: an elapsed window stops the glow" cleared). The fix required no hud_state edit (forbidden by the brief).
- `bash tests/run.sh` snapshots while the tree was being edited concurrently by other lanes: **35 steps, 4 failed at 14:04Z** (`paladin_state`, `hunter_guide_state`, `rotationtext_state`, `bars_state`) and **35 steps, 7 failed at 14:06:37Z** (`smoke`, `druid_state`, `paladin_state`, `druid_guide_state`, `hunter_guide_state`, `bars_state`, `wiring_check`) — every failing step in both snapshots belongs to another lane mid-landing. `warrior_state` and `hud_state` are **PASS in both**, and tree-wide luacheck reports **0 errors** in both (46 → 60 warnings, all other lanes' new files). The tree is moving under concurrent lanes; the claims that hold for THIS lane are the two suite lines above.
- `luacheck classes/warrior.lua tests/warrior_state.lua`: **0 errors**; 2 warnings on warrior.lua, both pre-existing (lines 558 trailing whitespace, 585 whitespace-only — original `set_bar_color` formatting, untouched). warrior_state.lua: 0 warnings. Tree-wide luacheck at snapshot: 0 errors.
- **Mutation proofs on `/tmp/opencode/mut_warrior/`** (full copy, byte-identical after restore):
  1. W2 rage gate threshold broken (`rage >= cost + reserved` → `... - 10`): **10 FAILs** (the predicate rows, the WW-fallback rows and the real-engine wrapper rows). Restored → warrior_state 620 PASS.
  2. Glow fix reverted to the old `or hud_usable_now(slot)` expression: **hud_state 1 FAIL** ("warrior: an elapsed window stops the glow") **+ warrior_state 2 FAILs** (the new mirrored pins). Restored → both suites green; copy diffed byte-for-byte against the repo.

## 5. bars_state — counts (later-wave reconciliation) and the one non-warrior failure

Brief: bars_state count expectations are a later wave; report the counts instead.

- **WARRIOR textures: 34 created vs stale expectation 33 → +1** = the W1 bank edge texture. **WARRIOR fontstrings: 19 vs 17 → +2** = the W1 "BANK" label + the Battle Shout badge FontString. WARRIOR frames: unchanged (all new widgets are textures/fontstrings on the existing visuals frame).
- The other bars_state count failures (PALADIN frames/textures/fontstrings; pre-init construction 28 vs 10) are paladin-lane additions, not warrior.
- **"glow: combat exit stops the glow (8 vs 7)" is NOT warrior-reachable — brief misattribution, evidence below.** The check lives in the PALADIN block of `tests/bars_state.lua` (line 1576; p4 = 6, after exit = 8). An instrumented `PixelGlow_Stop` on the /tmp copy traces the extra stop to `classes/paladin.lua:422 aow_exo_pulse_stop` ← `classes/paladin.lua:1428` (paladin's `on_combat_exit`) ← `bars_state.lua:1578`; the warrior frames appear nowhere in that trace. The paladin P6 pulse is stopped on combat exit even when it was never started (its `start` was the dead hook the paladin brief owns; the paladin lane has since wired the start at `paladin.lua:473` but the combat-exit stop at 1428 is still unconditional). A lifecycle guard there (stop only when armed) clears the check. Raised as **HU-4** in `hands-up.md` + escalation signal; warrior scope (`warrior.lua`/`warrior_state.lua`) cannot reach it.

## 6. UNCONFIRMED items (in-client list)

- **UNCONFIRMED:** in-client behavior of everything above — the addon was never loaded in a game client this round (offline harnesses cannot). Owner's test session should confirm the OP glow lifecycle (window armed/elapsed on a classic dodge; readiness glow on Retail/Forever), the W1 BANK cue band/floor, the W2 gate prompts, the W3 badge tiers and the BS badge.
- **UNCONFIRMED (pending in-client confirmation, per the brief):** Bloodthirst/Whirlwind rank ids and the 6 s / 10 s cooldown values (TBC 2.5.6 / Era 1.15.9); the guide/HUD swipes read them name-based where the API allows, ids as fallback.
- **UNCONFIRMED:** Battle Shout rank ids (6673 / 5242 / 6192 / 11551 / 25289 / 2048 / 47436; audit-page sourced) and the 120 s no-expiry fallback (Forever lists 3 min — a client that answers always wins).
- **UNCONFIRMED:** Rampage aura 29838 + 5-stack cap (name fallback covers); Overpower 7384 + localized-name match; Shield Block 2565; SoD Sudden Death aura 440495 (which id fires); Victory Rush 34428 + name on Forever; Bloodthrill aura name on Forever (name-only by design — no id guess); Bladestorm 90 s / Raging Blow 8 s / Mortal Strike 6 s swipe fallbacks; SoD HS floor 60 and Era reserve window 2.5 s; W1 band width 15 % and rage floor 60.
- **UNCONFIRMED:** whether the real clients' `IsSpellUsable` reports Overpower usable exactly on the proc (the W7 fallback's premise); the fallback's nil-stamp-only scope is the pinned offline contract either way.
- Options-pass items: wire `show_warrior_bank_cue` and `show_warrior_battle_shout_badge` widgets/defaults (false) and document the nil-off semantics.

Bench rule honoured: nothing overwritten; this is the warrior lane's single report file. Cross-references: `desks/warrior/journal.md`, `desks/warrior/.signals/20261017T140420Z.json` (+ the hands-up signal), `bench/briefs/brief_warrior_2026-10-17.md`, `bench/verify_bank.md` W1/W2/W3/W7 + §4.2 + §5.2/§5.3, `bench/discover_features.md` #9.
