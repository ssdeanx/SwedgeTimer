# bars-decouple (2026-10-28) — ranged/melee decoupling, offhand size, power-bar slot

Desk `bars-decouple`. Brief: `bench/briefs/brief_bars-decouple_2026-10-28.md`.
Write scope held exactly: `main.lua`, `bars.lua`, `power_bar.lua`, `config_presets.lua`,
`tests/bars_state.lua`, `tests/power_bar_state.lua`. No git, no TOC/version/lint-config/
`Libs/`/`docs/`/`classes/*`/`hunter_ui.lua` edits. Line endings unchanged (LF in all six).

Operator report driving the lane (2.1.3 tree, TBC Anniversary + Era), verbatim:
"off hand should be same size as mh, and should only show when using it. also power bar
should be below it." / "ranged bar shouldnt be below mh/oh bar because thats where power
bar should be for each class." / "ranged and melee are not the samething why are they
effecting each other?" / "why is ranged bar popping up when im using melee..." / "u need
to fix it so ranged isnt firing like that unless its actually being used."
Correction received in-session: **classic_era = Era, classic_anniversary = TBC** — no
family was guessed from a branch name anywhere below.

## 1. What changed (file:line, current tree)

### `main.lua`

- **`main.lua:589-628`** — per-hand activity state (`has_activity`, `last_activity_at`)
  initialised for mainhand/offhand/ranged in `OnInitialize`.
- **`main.lua:1110-1128`** — **offhand activity receipt** in the neutral CLEU handler: a
  player-sourced `SWING_DAMAGE`/`SWING_MISSED` with the `isOffHand` flag marks the offhand
  in use. Slots are the vendored library's own: return 21 on `SWING_DAMAGE`, return 13 on
  `SWING_MISSED` (`Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:399-407`).
- **`main.lua:1478-1487`** — **Forever engine receipt** in `SWING_TIMER_START`: on the
  `forever-source` engine only, a START for offhand/ranged is a receipt (that engine fires
  its START solely from a real `PLAYER_SWING`; `swing_source.lua:on_player_swing`). The
  classic library's START is deliberately excluded — see the reason in §2.1.
- **`main.lua:1925-1932`** — `SWING_RESET_SPELL_IDS` no longer carries Throw (2764),
  Shoot (3018) or Shoot Wand (5019): they are ranged SHOTS, and the addon's own
  utility-cast path was restarting the MELEE hands on them.
- **`main.lua:1984-2005`** — `RANGED_SHOT_SPELL_IDS` (75 Auto Shot, 3018 Shoot, 2764 Throw,
  5019 Shoot Wand — the ids the library's own `ranged_swing` tables key on every classic
  branch) + `is_ranged_shot_token` (id, or localized name via `api.GetSpellInfo`).
- **`main.lua:2020-2071`** — `ST:swing_player_unit()` (cached `STL.getUnit("player")`),
  `ST:arm_ranged_shot_reset_guard(spell_id, cast_name)` and its tick arm. The guard sets the
  engine's own `preventSwingReset` field — the field the library's cast-completion branch
  tests (`lib:596`) and recomputes per cast (`lib:683`) — so a completed shot no longer
  restarts mainhand + offhand on any class.
- **`main.lua:2147-2170`** — `UNIT_SPELLCAST_SUCCEEDED`: a completed shot token stamps the
  ranged hand's activity receipt (all four shot ids, not just Auto Shot).
- **`main.lua:2271-2288`** — `UNIT_SPELLCAST_START`: a player shot cast arms the reset guard.
- **`main.lua:2685-2688`** — `rf_update` (the 0.05 s poll) re-arms the guard while the
  engine reports a live cast, so library/AceEvent frame dispatch order cannot decide the
  outcome.
- **`main.lua:2731-2824`** — the **hand-activity rule** (`HAND_ACTIVITY_CYCLES = 2`,
  `HAND_ACTIVITY_MIN_SECONDS = 1.5`, `HAND_ACTIVITY_MAX_SECONDS = 8`) plus
  `hand_visibility_needs_activity`, `note_hand_activity`, `hand_activity_window`,
  `hand_is_in_use` (auto-repeat OR a receipt within two of the hand's own cycles).
- **`main.lua:2835-2888`** — `handle_bar_visibility` split into
  `hand_show_condition_met(hand, db)` (the old branch logic, exactly preserved) and the
  **activity gate** for offhand/ranged: the configured condition is the outer requirement
  ("always" keeps working), and the hand must genuinely be in use to show.

### `bars.lua`

- **`bars.lua:252-287`** — new `ST:hand_bar_size(hand, width_override, height_override)`:
  the offhand's width **and height** are read from the mainhand's table on every pass (an
  explicit per-pass override still wins; the offhand's own saved keys are never written).
- **`bars.lua:289-372`** — `configure_bar_size_and_positions(hand, width_override,
  height_override)` now sizes every frame from that pair (there was no height path before),
  and a mainhand configuration pass cascades to a built offhand in the same call, so a
  mainhand size change made in the options immediately resizes the offhand.

### `power_bar.lua`

- **`power_bar.lua:180-231`** — enablement (`usable_hand_frame`) split from visibility
  (`visible_hand_frame`). `choose_anchor` keeps the bar up only while a melee bar is on
  screen, then owns the slot **of the offhand ROW** when the class uses an offhand (whether
  or not that hand is currently drawn — its bar is activity-driven now), else the mainhand
  row. `pb.anchor_choice` keeps its pure contract with "available" instead of "visible"
  inputs.
- **`power_bar.lua:245-300`** — the layout latch now compares the owning frame's screen rect
  (`GetLeft`/`GetBottom`, rounded to 0.1 px) as well as its identity, so a bar that is
  dragged / re-anchored (the hunter melee stack does exactly that) re-points the power bar.
- Header PLACEMENT paragraph rewritten to the new rule.

### `config_presets.lua`

- **`config_presets.lua:1103-1120`** (Rogue) and **`config_presets.lua:1490-1507`**
  (Warrior) — the shipped ranged position moved from `y = -166` (the row directly below the
  melee stack, i.e. the power bar's slot) to `y = -98`, above the mainhand row, matching the
  hunter layout order. Comment states the slot rule and that a user's saved position stays
  theirs (the addon never re-anchors the ranged hand at runtime).

### Tests

- **`tests/bars_state.lua:3159-3420`** — new section 11 "bars-decouple": ranged/offhand
  never show from combat state; a real shot / real offhand swing does; the two-cycle window
  (one cycle later still up, two later hidden); auto-repeat as a ranged receipt; a mainhand
  swing is not an offhand receipt; a vendored engine START is not a receipt; Forever STARTs
  are; the operator's warrior scenario (ranged bar enabled, mainhand swinging → hidden, a
  shot → shown); offhand size invariant for WARRIOR/HUNTER/SHAMAN/ROGUE incl. a divergent
  saved offhand size and the options-driven cascade; the shipped ranged positions above the
  melee row; a Shoot no longer restarts the mainhand; the engine's reset guard arms for a
  shot cast (tick + event arms) and not for a melee cast.
- **`tests/bars_state.lua` fixture** — the vendored-STL stub gained the library's own
  `getUnit` accessor and a `sb.swing_unit` table (`casting`, `lastCastSpellId`,
  `lastCastName`, `preventSwingReset`), so the guard is exercised against the same fields
  the real library exposes.
- **`tests/power_bar_state.lua:325-360`** — new 5b: a moved/re-anchored owning bar re-points
  the power bar; a settled one does not (latched); a new bottom edge counts as a move.
  Section 5 re-cut to row ownership (below).
- Suite counts: `bars_state` 962 → **1040** checks, `power_bar_state` 151 → **190**.

## 2. Why the engine's START cannot be the receipt (the mechanism, re-checked)

The brief's framing ("ranged shows for warrior during mh swing; mh activates when ranged
goes off") has two separate mechanisms; both were reproduced offline:

1. **Visibility.** The old `either` condition showed every enabled hand in combat
   (`main.lua:2550-2562` before this change), so a warrior's ranged bar was up for the whole
   mainhand fight. Fixed by the activity gate (§1).
2. **The melee cycle restart on a shot.** The vendored library restarts mainhand + offhand
   on any completed cast while its own `casting` flag is up (`lib:596-605`), and Auto Shot /
   Shoot / Throw / Shoot Wand are exactly such casts and are not exempt (`noreset_swing_spells`
   bands end at `:1044`, `:1167`, `:1448`, `:1560`, `:1668`, `:1713` — no `[75]` in any of
   them). The previous lane proved this on the real library
   (`bench/bars_range_hunter_2026-10-25.md` §4.2-4.3: "Anniversary (5, 1) Auto Shot 75 →
   START:mainhand, START:offhand, START:ranged"). `classes/hunter.lua` already arms the
   library's `preventSwingReset` for hunters; nothing did for warriors/rogues. The generic
   guard in §1 is that fix; the same field, the same cast window.
3. **Our own path too.** `SWING_RESET_SPELL_IDS` listed Shoot/Throw/Shoot Wand as
   "utility resets" and restarted mainhand + offhand from them. Removed from that list;
   those ids now flow through the shot path only.
4. **Why not stamp from `SWING_TIMER_START`:** the library also starts cycles from
   `PLAYER_ENTER_COMBAT` (`lib:745-752`), `PLAYER_EQUIPMENT_CHANGED` (`lib:730-743`), any
   resetting cast (`lib:596-605`), Feign Death (`lib:640-650`) and, on Wrath/Cata, from
   every melee swing (`lib:740-742`). Stamping those would have re-introduced "appears
   because combat started" and a Wrath-only cross-family leak.

## 3. Offline verification (all run on this tree)

- `bash tests/run.sh`: **54 steps, 0 failed**; luacheck **2 warnings / 0 errors in 97 files**
  (the pre-existing pair: `compat.lua:36` unused `addon_name`, `main.lua:87` `table.pack`).
- `lua5.1 tests/bars_state.lua` → PASS, 1040 checks. `lua5.1 tests/power_bar_state.lua` → PASS,
  190 checks.
- **Mutation proofs** (fresh full-tree copies under `/tmp`, `rsync -a --exclude=Media
  --exclude=docs --exclude=.git --exclude=.desks --exclude=bench`, removed afterwards):
  11/11 killed.

| # | mutation | killed by |
|---|---|---|
| M1 | activity gate removed | 9 red, incl. "combat + target alone never shows the ranged bar" |
| M2 | receipt is a no-op | 12 red, incl. shot/offhand receipts |
| M3 | vendored START counts as receipt | "a vendored engine START is not an activity receipt" |
| M4 | Shoot back in the melee-reset list | "a Shoot does not restart the mainhand cycle" |
| M5 | shot guard inert | "a live shot cast arms the engine's melee-reset guard" |
| M6 | offhand size invariant removed | "a divergent saved offhand width renders at the mainhand's" (17 red) |
| M7 | mainhand→offhand cascade removed | "a mainhand width change resizes the offhand" |
| M8 | ranged default back to y -166 | both ranged-position pins (2 occurrences replaced) |
| M9 | power bar follows visibility again | "an idle (hidden) offhand keeps its row" |
| M10 | power-bar identity-only latch | "a moved owning bar re-points the power bar" |
| M12 | CLEU offhand receipt dropped | "an offhand swing marks the offhand in use" |

The guard's *mechanism* (setting `preventSwingReset` suppresses the melee restart at the
shot's completion) is the one already proved against the **real** vendored library by the
2026-10-25 lane (`bench/bars_range_hunter_2026-10-25.md` §4.3: "Auto Shot SUCCEEDED with
preventSwingReset=true → SWING_TIMER_START hand=ranged (only)"; pinned in
`tests/hunter_state.lua` §14m). This lane re-verified the field names against the real file
(`lib:596` tests it, `lib:675/681` write `lastCastName`/`lastCastSpellId`, `lib:683` sets
`casting`) and that the real library exposes `getUnit` (`lib:264`); it did not re-run that
real-engine harness (the suite that owns it, `tests/real_wire_state.lua`, is outside this
lane's write scope).

## 4. Test pins re-cut (and why)

1. `tests/power_bar_state.lua` §5 — **genuinely invalidated by this lane**: the old pin
   "a hidden offhand falls back to the mainhand" encoded visibility-based ownership; A5/A1
   make the offhand ROW own the bottom slot. Re-cut to "an idle (hidden) offhand keeps its
   row: the bar does not hop to the mainhand", plus new pins for the no-offhand class and
   for an offhand-only visible group. The suite's `ST.bar_is_enabled` stub was corrected to
   model enablement (a real class's `bar_is_enabled` never reads `IsShown`), which is what
   made the old pin pass.
2. `tests/power_bar_state.lua` — `pb.anchor_choice` labels changed "visible"→"available"
   (pure helper, same semantics).
3. `tests/bars_state.lua` hunter queue tint pin — **NOT invalidated by this lane**: the
   parallel `hunter-tint` lane's B1 contract (a queue tint only paints on a live mainhand
   cycle) left that pin asserting a tint with no cycle. Re-cut by bringing the fixture into
   melee (`in_combat = true` + one mainhand swing) before the queue assertions. Flagged for
   the orchestrator: that lane owns the contract, this lane owns the file.

## 5. UNVERIFIED in client (no in-client session for this lane)

- **U1** — any of it on a live client. Everything above is offline (stubbed frame/engine).
  Specific in-client questions: (a) does a warrior's/rogue's `UNIT_SPELLCAST_START` fire for
  Auto Shot on Era/TBC (the guard's precondition — the same flag the leak keys on, so a
  client that never reports it also never leaks); (b) does `preventSwingReset` suppress the
  melee restart on the operator's TBC build (the 2026-10-25 real-library proof says yes for
  Anniversary); (c) does the ranged bar hide promptly after a shot burst with no flicker at
  the operator's auto-shot speed.
- **U2** — the power bar's position under an *idle-but-enabled* offhand row (a one-row gap
  where the offhand appears). This is the intended A5 layout but it is a visual judgement
  only the operator can make.
- **U3** — the offhand's activity window feel: a receipt lasts `min(2 cycles, 1.5 s…8 s)`.
  For a 2.6 s mainhand / 1.5 s offhand that is 3 s after the last offhand swing.
- **U4** — Wrath/Cata residual: those library branches also list Auto Shot/Shoot/Throw in
  `reset_swing_spells` (`lib:1159-1163`, `lib:1438-1441`), so their first clause restarts melee
  regardless of `preventSwingReset`; the guard is inert there (documented, lib untouched).
  Not testable here (no Titanforge client) and not the operator's reported family.
- **U5** — hunter side-effect of hiding the ranged bar: `hunter_ui.lua` parents its cast bar,
  range helper, Rapid Fire bar and badges to the ranged bar frame, and they tick from the
  ranged bar's OnUpdate. While the ranged bar is hidden they cannot paint (a pre-existing
  frame ownership, now reachable more often). Normal Auto Shot play keeps the bar up through
  the two-cycle window; a standalone cast with no recent shot is the gap. The durable fix is
  a hunter-owned always-visible driver in `hunter_ui.lua` (outside this lane).

## 6. Operator decisions left open

- **D1 — the `Always` show option for the ranged/offhand hand.** The activity gate is
  absolute for those two hands: "Always" now means "no combat/target condition" but the hand
  still must be in use. The alternative (honour "Always" literally, bar up forever) would
  reproduce the reported complaint. If the operator wants `Always` to win, say so and the
  gate moves behind it — one line in `handle_bar_visibility`.
- **D2 — the per-hand offhand Width/Height options are now inert** (the mainhand's size is
  the offhand's, per the order). The honest UI fix is to hide/lock those two widgets for the
  offhand hand in `option_tables.lua` (not this lane's file). No saved key is rewritten.
- **D3 — existing profiles keep their saved ranged position.** The shipped default moved
  (rogue/warrior -166 → -98), but AceDB never overwrites a saved key, so a profile that
  already has the ranged hand parked under the melee stack still parks it there (A1 says the
  ranged hand keeps its own saved position). If the operator wants their own profile fixed,
  that is a drag, a profile reset, or a small one-time migration the options pass could own.
- **D4 — a "hands only while in use" switch?** None was added (the order is the default).
  Nil-safe if the options pass ever wants one: `hands_require_activity ~= false`.
- **D5 — looked at, not fixed (out of scope): the standalone ranged-distance bar**
  (`weave_range.lua`, hunter default ON) shows whenever there is an attackable target with a
  known distance — including while meleeing at 3 yards (state "MELEE"). That is the other
  widget that can read as "a ranged bar popping up while meleeing". `weave_range.lua` is not
  in this lane's write scope; flagging it as a follow-up candidate.

## 7. Files changed

- `main.lua` (activity rule + visibility split + shot receipts + generic shot→melee reset guard)
- `bars.lua` (height override + offhand = mainhand size invariant + cascade)
- `power_bar.lua` (row ownership below the melee stack + rect-change re-pointing)
- `config_presets.lua` (rogue/warrior ranged default above the melee row)
- `tests/bars_state.lua` (new section 11 + fixture `getUnit` surface)
- `tests/power_bar_state.lua` (row-ownership pins + movement pins + fixture enablement split)

No CHANGELOG/README/TESTING edit (outside the lane): suggested bullet for the docs reconcile —
"Ranged and offhand bars are visible only while those hands are actually in use; the offhand
renders at the mainhand's size; the power bar owns the slot under the bottom-most melee row
and follows it; a ranged shot no longer restarts a melee swing."
