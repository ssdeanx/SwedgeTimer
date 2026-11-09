# Hunter main-hand tint: melee-cycle gate + immediate clears (2026-10-28)

Desk: `hunter-tint`. Brief: `bench/briefs/brief_hunter-tint_2026-10-28.md`.
Lane write scope: `classes/hunter.lua`, `hunter_ui.lua`, `tests/hunter_state.lua`.
Client context: operator on TBC Anniversary (family TBC) and Classic Era. **No in-client
session was available to this lane — every claim below is offline evidence; the in-client
list is in §6 and is not papered over.**

## 1. Operator report and root cause

Verbatim: *"why is mh changing colors for hunter when using ranged"* / *"the only thing the
bar does is change color when im using ranged"* / *"ranged and melee are not the samething
why are they effecting each other"*. The operator's `/st diag` showed
`swing_mainhand=35/0/29`, `swing_ranged=230/0/190`, `errors none` — the melee wire is alive,
so this was a colour/state problem, not a missing swing.

Root cause (re-verified in the tree, not assumed): the only runtime writer of a hunter
main-hand fill colour is `ST.HUNTER.set_bar_color` (`classes/hunter.lua`). It painted the
Raptor Strike tint (shipped ON) or the Steady Shot tint (shipped off) whenever the matching
queue flag was true — with **no check that the main-hand had a melee cycle at all**. The
flags are set by `on_current_spell_cast_changed` from `IsCurrentSpell` probes and cleared by
several `on_spellcast_*` paths; the clear paths set the flag false and did **not** repaint,
and `on_combat_exit` cleared both flags without repainting. So a tint applied at any point
could outlive its melee context and stay on the fill through a ranged stretch. There was
also no target-change clear.

The reference has the same lifecycle solved three ways, which this lane ports:
`IsHunterMeleeActive` (hunter + in combat + mh timer "swinging",
`SuperSwingTimer_State.lua:455-464`), `OnMeleeSwing` (a real MH swing restores the base
colour, `SuperSwingTimer_ClassMods.lua:5857-5863`), and `ClearHunterQueueTint` (restores
unconditionally on the interrupt/fail/queue-clear paths, `:5870-5877`). The reference also
polls the queue every 0.1 s (`UpdateHunterQueueTint`, `:5800-5834`); this tree is
event-driven, so the equivalent safety net is a per-frame maintenance tick (§2.3).

## 2. What changed

### 2.1 `classes/hunter.lua` (CRLF preserved; the only addon file this lane changed)

- `classes/hunter.lua:154-181` — new file-scope predicate `hunter_mainhand_cycle_live(self)`:
  `self.in_combat == true`, `self.mainhand` is a table, `is_full ~= true`,
  `engine_dead ~= true`, `speed > 0`, numeric `start`/`ends_at`, and
  `api.get_time() < ends_at`. This is the B1 gate: a live melee swing cycle only. Every read
  is nil-safe (Retail stand-in / pre-init sandbox), and the clock is the aligned
  `api.get_time()` domain the engine's expiration stamps live in. 179 file-scope locals
  (limit 190, headroom 21; toc_check prints it).
- `classes/hunter.lua:1414-1470` — `set_bar_color`:
  - B1: after the `hand ~= "mainhand"` return, `if not hunter_mainhand_cycle_live(self) then
    return false end` — the fill hands back to bars.lua's default whenever there is no live
    melee cycle, so a queue flag can never recolour the fill at range (or out of combat, or
    on a full/dead/expired cycle). The flags are deliberately **not** cleared here (the
    event-driven flag semantics stay intact; the maintenance tick clears them, §2.3).
  - B2 "swing consumed": main.lua calls this hook at every `SWING_TIMER_START`
    (`main.lua:1479` at report time — main.lua was being edited by the parallel
    `bars-decouple` lane, so the citation is as-of-this-report, not a stable pin); when the
    observed `mainhand.start` moved, a new swing has consumed the queued next-attack, so
    both flags are dropped and the base fill is restored in the same call (reference
    `OnMeleeSwing`). The first observation (`nil` → a start) is not a consumption.
  - The target the tint is painted against is stamped (`hunter_tint_target =
    UnitGUID("target")`) for the target-change clear.
- `classes/hunter.lua:1384-1400` — `on_combat_exit`: clears both flags **and** repaints the
  main-hand fill in the same path (B2; reference `ClearHunterQueueTint`). The repaint
  carries the `interfaces_are_initialised` guard, because it touches bar visuals — the same
  contract the paladin's combat-exit glow stop satisfies (wiring_check check 3).
- `classes/hunter.lua:1136-1145` / `:1170-1178` — the `on_current_spell_cast_changed` clear
  branches: when the branch actually drops a true flag it repaints immediately (B2); when
  the flag was already false it stays a plain clear. This is the branch the ranged-play
  stale tint leaked through (flag dropped, fill kept).
- `classes/hunter.lua:1240-1268` — new `ST.HUNTER.maintain_queue_tint(self)`: the per-frame
  safety net. Only runs while a queue flag is true (idle cost: two boolean reads). Clears
  both flags and repaints when the melee cycle is no longer live (B1) or when
  `UnitGUID("target")` no longer matches the target the tint was painted against (B2 target
  change). Reads only the flags, the main-hand cycle, the target GUID and the clock —
  **never `self.ranged`** (B4).
- `classes/hunter.lua:1284-1289` — `on_bar_update` calls the maintenance **ahead of the hand
  gate** (the `update_trap` / shot-guard pattern), so whichever bar ticks clears a stale
  tint; the main-hand bar's OnUpdate stops while that bar is hidden, the ranged bar keeps
  ticking. Player-level state, not a ranged read.
- `classes/hunter.lua:1184-1190` — `post_init` initialises `hunter_tint_swing_start` /
  `hunter_tint_target` to nil (session state; a reload cannot inherit a half-written tint).

`hunter_ui.lua` is **unchanged** (md5 `d899ef5f76f70cf8a7a860068dc59fe4`, verified before and
after). It was in scope, but no UI change was needed: B4 forbids touching `self.ranged`
visibility/range state, and the class module already owns the fill.

### 2.2 Requirement mapping

| Req | Evidence |
|---|---|
| B1 tint only on a live MH melee cycle, cleared when the cycle is gone | §2.1 predicate + `set_bar_color` gate + maintenance tick; pins "B1: a queued tint with no main-hand cycle claims no colour (ranged play)", "B1: the main-hand fill is never recoloured during ranged play", "B1: every non-live shape is refused", "B1: the tick clears the flag when the cycle is gone" |
| B2 every clear path repaints (swing consumed / combat exit / target change / current-spell clear) | §2.1 five paths; pins "B2: the swing that consumes the queue restores the default fill", "B2: combat exit repaints the main-hand fill", "B2: a target change repaints from the RANGED tick", "B2: the current-spell clear repaints the main-hand fill", plus re-cut sections 4/5/8/9 |
| B3 existing keys/defaults keep working in melee, no shipped default flipped | Raptor/Steady tint matrices re-armed on a live cycle and still paint the configured colours; source pin "B3: the shipped Raptor tint default is still ON" / "…Steady… OFF" reads `config_presets.lua` unchanged |
| B4 no new cross-hand coupling | Runtime pin "B4: a live ranged cycle does not keep the main-hand tint alive"; structural pins scan the predicate, `set_bar_color` and `maintain_queue_tint` bodies for `self.ranged` (none); `hunter_ui.lua` untouched |

### 2.3 Design note: why a tick and not an event

`main.lua` owns event registration and has no class dispatch for target changes
(`PLAYER_TARGET_CHANGED` is not registered; `PLAYER_TARGET_SET_ATTACKING` / `UNIT_TARGET`
have no class hook), and `main.lua` is out of this lane's write scope. The maintenance tick
is therefore the in-scope equivalent of the reference's poll: it runs only while a tint is
queued, and only a `UnitGUID` compare + a repaint in that window. The swing-consumed clear
does not poll at all — it rides the existing `SWING_TIMER_START` → `set_bar_color` call.

## 3. Offline verification

### 3.1 Gate

- Baseline at lane start: `bash tests/run.sh` → **54 steps, 0 failed**; luacheck 2 warnings /
  0 errors in 97 files.
- Final: `bash tests/run.sh` → **54 steps, 0 failed**; luacheck **2 warnings / 0 errors in
  97 files** (the two pre-existing: `compat.lua:36` unused `addon_name`, `main.lua:87`
  undefined `table.pack`). `luacheck classes/hunter.lua hunter_ui.lua
  tests/hunter_state.lua` → 0 warnings / 0 errors in 3 files.
- `tests/hunter_state.lua`: **1909 checks, PASS** (baseline 1843; +66 for the new section
  and the fixture/pin changes).
- `tests/toc_check.lua`: `classes/hunter.lua: 179 locals … headroom 21`.
- `tests/wiring_check.lua`: 879 checks, 0 failures, 3 accepted known defects, 0 stale.

### 3.2 Pins re-cut in `tests/hunter_state.lua` (this lane's file)

| Pin | Was | Now | Why |
|---|---|---|---|
| §3 pre-init recolour count | 4 | 4 (label/comment re-cut) | combat exit now dispatches a recolour, but only behind the `interfaces_are_initialised` guard the wiring check requires, so the pre-init count is unchanged; the comment records the guard |
| §4 "clearing a stale queue …" | 0 recolours | 1 recolour | B2: the clear branch repaints |
| §4 option-off block | inherited the previous counter | counter reset to 0 | the previous clear now repaints; the option-off path must still not |
| §5 "combat exit does not recolour by itself" | 0 | 1 | B2 |
| §8 "clearing a stale steady queue …" | 0 recolours | 1 recolour | B2 |
| §9 "combat exit does not recolour by itself" | 0 | 1 | B2 |
| §4/§6/§8/§10 tint matrices + §8 TBC channel sub-sandbox | queued flag painted with no cycle | fixture arms a live cycle (`arm_melee_cycle`) | B1: a tint without a live cycle is now refused by design |
| `build()` fixture | no `ST.mainhand` | `ST.mainhand = { is_full = true }` (main.lua:582-591 idle shape) + opt-in `UnitGUID` stub | faithful client shape; keeps the sandbox nil-safe |
| new §10c | — | 66 checks | B1/B2/B3/B4 proofs (see §3.3) |

**Cross-file pin (filed, not edited by this lane):** `tests/bars_state.lua` is owned by the
parallel `bars-decouple` lane. Its HUNTER pin *"the mainhand bar takes the Raptor Strike
tint"* asserted the tint with no main-hand cycle (`ST.in_combat` nil, no swing) — exactly
the bug B1 removes, so it could not survive. This lane did **not** edit the file; it filed
the minimal re-cut to the orchestrator (`ST.in_combat = true` + `start_swing(b, "mainhand",
2.6, 2.6)` before the queue event, proven on a `/tmp` copy: bars_state 962/0, hunter_state
1909/0). The owning lane landed an equivalent re-cut itself at 03:24 (`tests/bars_state.lua`
"Re-cut 2026-10-28", with `sb.clock = 41.5` and the same swing arm); the full gate is green
with it.

### 3.3 Mutation proofs (each on a `/tmp/opencode` copy; source tree untouched)

Seven mutations of `classes/hunter.lua`, each re-run against `tests/hunter_state.lua`; every
mutation was killed by at least one new pin:

| Mutation | Killed by |
|---|---|
| M1 remove the B1 live-cycle gate | "B1: a queued tint with no main-hand cycle claims no colour (ranged play)", "B1: the main-hand fill is never recoloured during ranged play" |
| M2 remove the swing-consumed clear | "B2: the swing that consumes the queue restores the default fill" |
| M3 remove the combat-exit repaint | "combat exit repaints the main-hand fill" |
| M4 revert the current-spell clear to a silent flag drop | "clearing a stale queue repaints the fill immediately", "B2: the current-spell clear repaints the main-hand fill" |
| M5 remove the maintenance call from `on_bar_update` | "B2: a target change repaints from the RANGED tick", "B1: the tick clears the flag when the cycle is gone" |
| M6 remove the target-GUID check | "B2: a target change drops the queue flag" |
| M7 make the predicate read `self.ranged` | "B4: the live-cycle gate never reads self.ranged", "B4: a live ranged cycle does not keep the main-hand tint alive" |

The first mutation run exposed a fixture gap (the sandbox had no `ST.mainhand`, so removing
the gate crashed before the B1 pins could run); the fixture now mirrors main.lua's idle hand
shape, and M1 is killed cleanly. Recorded because it is the difference between a pin that
passes and a pin that cannot fail.

## 4. Behaviour summary (offline model)

- At range: a queue flag (from any source) can never paint the fill; if one is set, the next
  bar tick drops it and repaints. A live **ranged** cycle does not keep the tint alive.
- In melee: a genuinely queued Raptor/Steady still paints the configured colour while the
  main-hand cycle is live (B3), and the paint is cleared by the swing that consumes it, by
  combat exit, by a target swap, or by the current-spell clear — each in its own path.
- No shipped default changed: Raptor ON (red 207,58,83), Steady OFF.

## 5. Files changed by this lane

- `classes/hunter.lua` — the fix (CRLF preserved; `file` verified before and after).
- `tests/hunter_state.lua` — re-cut pins + new §10c (66 checks) + fixture shape.
- `hunter_ui.lua` — **unchanged** (md5 verified).
- `bench/hunter_tint_2026-10-28.md` — this report.
- `desks/hunter-tint/journal.md`, `desks/hunter-tint/.signals/…json` — desk trail.

Not touched: `main.lua`, `bars.lua`, `power_bar.lua`, `config_presets.lua`, `Libs/`, any
TOC, `.luacheckrc`, `tests/run.sh`, `docs/`, `tests/bars_state.lua`.

## 6. UNVERIFIED in client (no in-client session)

1. **The trigger itself.** Why the queue flag was set during the operator's ranged play
   (e.g. `IsCurrentSpell` answering true for a Raptor Strike probe on TBC Anniversary) was
   never observed. The fix makes the tint impossible at range **regardless** of how the flag
   was set, but the exact trigger remains UNVERIFIED. A `/st diag` or a
   `/run print(ST.raptor_strike_queued)` during ranged play would close it.
2. **Tick coverage.** The clear relies on at least one visible bar ticking. The ranged bar
   normally does; if every bar is hidden, the clear is deferred until one shows (the tint is
   not visible in the meantime, but a hidden fill could be stale on re-show for one frame).
3. **`UnitGUID("target")`** on the TBC Anniversary / Era clients: standard global, not
   observed in this lane; if a client cannot answer, both sides are nil and no target clear
   fires (the swing-consumed and current-spell clears still apply).
4. **The `now < ends_at` expiry edge** vs the bar's 0.5 s `bar_full_delay` window: reasoned
   from main.lua's field writes, not observed in client.
5. **Event ordering** between the swing-start `set_bar_color` call and Raptor Strike's
   `UNIT_SPELLCAST_SUCCEEDED` on the operator's client (both clear paths repaint, so either
   order is safe, but the visible timing is unobserved).
6. **Visual confirmation** that the MH fill returns to the default colour immediately during
   ranged play / on target change, and that the Raptor tint still visibly works in melee.
7. **Combined-tree state.** The parallel `bars-decouple` lane was editing `main.lua`,
   `bars.lua`, `power_bar.lua`, `config_presets.lua`, `tests/bars_state.lua` throughout this
   lane; the offline gate is green on the combined tree at this report's time, but the
   in-client combination of both lanes' changes is unverified.

## 7. Operator decisions left open

1. **Keep the Raptor tint default ON** now that it is melee-gated (this lane did not flip it;
   the journal lists the decision). Arguments: it is now safe at range, and it is the only
   visible melee cue on the MH fill; against: the operator's report was about the colour at
   all, and a bar that changes colour only in melee may still surprise.
2. **Steady Shot tint** stays shipped OFF; enabling it now behaves the same way (melee-gated).
3. Whether the MH bar should be **hidden** rather than merely default-coloured at range is
   the `bars-decouple` lane's visibility work, deliberately out of B4 scope here.
