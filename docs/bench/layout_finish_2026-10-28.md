# layout-finish (2026-10-28) — ranged placement, melee pair height, per-hand diag state

Desk `layout-finish`. Brief: `bench/briefs/brief_layout-finish_2026-10-28.md` (second wave of
the 2026-10-28 bar work; the first wave — `bars-decouple` + `hunter-tint` — landed earlier
today). Write scope held exactly: `main.lua`, `bars.lua`, `power_bar.lua`,
`config_presets.lua`, `option_tables.lua`, `option_table_presets.lua`, `diag.lua`,
`tests/diag_state.lua`, `tests/bars_state.lua`, `tests/power_bar_state.lua`,
`tests/options_load_state.lua`. No git, no version bump (2.1.3), no TOC / `Libs/` / docs /
`.luacheckrc` / `tests/run.sh` / `config.lua` / `weave_range.lua` / `hunter_ui.lua` /
`classes/*` edits. LF endings preserved and no trailing-newline state changed in the two
files that ship without one (`config_presets.lua`, `option_tables.lua` — both edited
mid-file only).

Operator orders this lane answers, verbatim:
1. "the ranged bar for other melee classes should be moved."
2. "Also do client for all melee, i dont want ranged showing up on rogue sameway it does for
   warrior."
3. "off hand should always be same width as main hand. maybe have it so u can adjust the
   height for both."
4. "distance bar has nothing to do with mh bar ... just supposed to help me ... know when i
   am within actual melee range." (L4: `weave_range.lua` out of scope, untouched.)
5. "/st diag works better, because it said there was no errors, meaning something was
   missed/silent." (L5: per-hand BAR STATE.)

## 1. L1 — the ranged hand is moved out of the power-bar row at RUNTIME

`bars.lua:324-549` (the rule) + `main.lua:428-433` (the one call).

- **`bars.lua:349-367`** — the rule's constants: `ST.RANGED_PLACEMENT_FLAG`
  (`"ranged_placement_213"`, per-class latch), `ST.SHIPPED_HAND_X/POINT/SCALE`
  (0 / "CENTER" / 1), `ST.RANGED_SHIPPED_DEFAULT_YS` (`-166`, `-120`, `-98` — every y this
  addon has ever shipped for the ranged hand) and `ST.RANGED_PLACEMENT_GAP` (2 px).
- **`bars.lua:370-391`** — `ST:saved_row_extent(hand)`: a saved row's (top, bottom) at the
  shipped anchor, or nil when the row is not readable (non-CENTER point, non-1 scale,
  missing y/height). No guessing.
- **`bars.lua:393-434`** — `ST:melee_reserved_band()`: the no-go band = the melee stack's
  own saved extent (every owned hand except ranged) **plus the power-bar slot** hanging one
  `pb.GAP` + the clamped class height under its bottom edge. The power-bar module is read at
  call time (`st.power_bar`, loaded after `bars.lua` in the TOC) and a sandbox without it
  falls back to the shipped 2 px / 14 px constants. The slot is reserved even while the
  power bar itself is switched off: the operator's rule is about the ROW, and a reserved row
  cannot start colliding again when the bar is switched back on.
- **`bars.lua:436-446`** — `ST:row_intersects_band()`: real overlap only; touching edges do
  not collide.
- **`bars.lua:448-465`** — `ST:shipped_ranged_y()`: the class's own shipped ranged y
  (`config_presets.lua`), else the shared bar default. Read-only.
- **`bars.lua:483-549`** — `ST:migrate_ranged_placement(profile)`: returns
  `"moved" | "kept" | "done" | "no-ranged" | "unknown"`. It re-places the ranged row ONLY
  while all of this holds: the row is still exactly a shipped default (`x=0`,
  `point="CENTER"`, `scale=1`, y in the shipped set) AND that row demonstrably intersects
  the reserved band. The replacement is the class's shipped ranged default when that clears
  the band, else `ceil(band_top + gap + ranged_height/2)`, so a migrated profile lands where
  a fresh one does. It writes `x/y/point/scale` of the RANGED row only and latches the
  CLASS row (`rawget`, see §5), so it can never run twice, cannot hop per tick and cannot
  fight a later drag. When it actually moves a row it says so ONCE through the addon's
  single chat path (best-effort, pcall'd), so a changed saved position is never silent.
- **`main.lua:428-433`** — the single call, right after AceDB is created and before
  `set_opts()`: pcall'd, so a bad profile cannot abort login and a sandbox without `bars.lua`
  is a no-op.
- **`config_presets.lua:1125-1133` / `:1514-1522`** — the rogue/warrior ranged-default
  comments no longer claim "the addon never re-anchors the ranged hand at runtime"; they now
  point at the rule and state that a dragged position is never touched.

**Which classes are covered.** The rule is driven by the addon's own hand set
(`has_hand("ranged")`), not by a class list. `main.lua:98-109` gives a ranged hand to
HUNTER, MAGE, PRIEST, ROGUE, WARLOCK and WARRIOR only; PALADIN, SHAMAN and DRUID have no
ranged bar at all (`class_hands` = mainhand [+offhand]), so for them the rule returns
`"no-ranged"` — there is no bar to move, and the day one of those classes gains a ranged hand
the rule covers it with no edit. That is the honest reading of the operator's "for other
melee classes": of the six shipped melee classes, three do not own a ranged bar.

**Existing-profile behaviour (the operator's actual complaint).** A profile created before
today's default move still holds `y = -166` for rogue/warrior: with the stock rows
(`mainhand -120`, `offhand -142`, power slot down to `-168`) that row spans `-158.5..-173.5`
and sits exactly in the power row, so the rule moves it once to the shipped `-98` on the
next login. A profile already at `-98` is left alone (`"kept"`); a dragged position (a
different x / y / point / scale) is never touched.

## 2. L2 — ROGUE behaves exactly like WARRIOR

The first wave's activity gate is already class-agnostic (`main.lua:2753-2756`
`hand_visibility_needs_activity` names HANDS, never classes). This lane verified it instead of
assuming it, and pinned it (`tests/bars_state.lua` §12d): for BOTH Warrior and Rogue, with the
ranged bar enabled — combat + an attackable target alone never shows the ranged bar; a real
completed shot (Throw 2764 / Shoot 3018) shows it; it hides again one activity window later;
a mainhand swing never surfaces it. Two source pins stop a future regression: the gate's body
contains no `player_class` reference, and it covers `"offhand"` + `"ranged"` by hand name. No
code change was needed for L2 — stating that plainly, because "nothing to fix" is a result.

## 3. L3 — ONE adjustable height for the melee pair

- **`config_presets.lua:115-128`** — the key is documented next to the power-bar keys:
  `melee_bar_height` (class row). **Shipped value: nil**, so there is deliberately no entry
  (AceDB stores no default; a profile saved before the key existed reads the shipped
  behaviour). Nil-safe: nil / `false` / any non-positive value = off; a positive number =
  both melee bars render at it. The ranged hand is never part of the pair.
- **`bars.lua:274-290`** — `ST:melee_pair_height()` reads the key with `rawget` (see §5) and
  returns nil for anything that is not a positive number.
- **`bars.lua:292-330`** — `ST:hand_bar_size()`: the pair height is authoritative for
  `mainhand` and `offhand`; the offhand's follow-the-mainhand branch now reads the mainhand's
  **effective** height (pair first, else its own key) so the pair cannot be silently undone.
  Width behaviour is unchanged: the offhand is always the mainhand's width (first wave).
- **`option_tables.lua:7383-7454`** — the widget: `Melee pair height (both hands)` (range
  6..60, step 1) sits in the Positioning panel at order 3.52/3.53 — right after the last
  melee hand's Height and before the ranged hand's group — plus the header/description and a
  `Use each hand's own height` execute button that clears the key (the real nil path). Only
  classes that own both melee hands get the block (the hand set decides, not a class list).
- **No lying per-hand height options** (`option_tables.lua:7239-7306` and the handler at
  `:1336-1510`, `option_table_presets.lua:254-272`):
  - Positioning → Mainhand Height shows the pair height and is locked while the pair is set;
  - Positioning → Offhand Height is **always** locked: the offhand renders at the mainhand's
    height (or the pair's), so its own saved key never sizes the bar and showing that number
    would be a lie. It shows the effective height and says it follows the mainhand;
  - the Appearance panel's Height widget (shared across hands, so it cannot be locked
    per-hand) shows and edits the same effective value: the handler's `bar_height` getter
    returns the pair height (melee hands) or the mainhand's height (offhand) and its setter
    writes the pair key / the mainhand key instead of the inert per-hand key. The widget's
    description says so. No saved key is rewritten by any of this.

Note the honest consequence: the offhand's own `bar_height` key has been inert since the
first wave; this lane makes the UI tell the truth about it rather than hiding the fact.

## 4. L4 — the distance bar is untouched

`weave_range.lua` is byte-identical to the pre-session baseline (sha256 `480b70e8…`). No
edited file references it beyond the pre-existing calls in `main.lua`'s post_init and the
options enable toggle, and no new code gates, moves or reads it. Proven by hash, not by
assertion: see §10.

## 5. L5 — `/st diag` per-hand BAR STATE

`diag.lua:435-621` (builders) + `:900-912` (report wiring).

One line per hand the class actually owns (the addon's `class_hands`, read-only; the
three-hand fallback exists only for an unreadable table:

```
SwedgeTimer diag: bar mainhand built=yes shown=yes alpha=1.00 tick=yes start=100.00 speed=2.60 ends_at=102.60 now=101.30 progress=0.500 full=no paused=no dead=no vf_width=271.00 fill=135.50 pos=0,-120 queue=raptor:no,steady:yes
SwedgeTimer diag: bar offhand built=yes shown=yes alpha=1.00 tick=yes start=100.00 speed=2.60 ends_at=102.60 now=101.30 progress=0.500 full=no paused=no dead=no vf_width=271.00 fill=135.50 pos=0,-142
SwedgeTimer diag: bar ranged built=no shown=? alpha=? tick=? start=? speed=? ends_at=? now=? progress=? full=? paused=? dead=? vf_width=? fill=? pos=0,-98
```

Fields, in order: `built` (HU-22 frames exist), `shown` (on screen right now), `alpha` (the
out-of-range dim writes it), `tick` (an OnUpdate script is installed on the bar frame),
`start` / `speed` / `ends_at` / `now` / `progress` (the cycle the tick renders from),
`full` / `paused` / `dead` (the branch flags), `vf_width` (the width the fill maths uses),
`fill` (the fill texture's actual width in px — 1 = the neutral sliver), `pos` (the saved
LibWindow row) and, on the MAINHAND line only, the hunter `queue=raptor:…,steady:…` flags
(class-level flags that recolour the mainhand fill). This is what makes the silent faults
visible without a debugger: a bar can be unbuilt, hidden, dimmed, unticked, stalled at
`progress=0.000`, or parked in the wrong row (`pos=`) with nothing thrown.

Print-only and nil-safe exactly like the rest of the module: frames are READ
(`IsVisible`/`IsShown`/`GetAlpha`/`GetScript("OnUpdate")`/`GetWidth`), every probe is
pcall'd, an unknown field renders `"?"` and an absent profile row renders `pos=?,?` — never
an error, and (deliberately) never a write: the profile row is read with `rawget`. The
section goes through the existing `append_section` so a binding cap prints the explicit
`bars +N more (cap N)` line instead of a silent cut.

`diag.MAX_LINES` moved 85 → **88** (one line per new hand line) so the error ring keeps its
full headroom and the ids tail is unchanged; the two `or 85` fallbacks now share a
`DEFAULT_MAX_LINES` local. Reported here because the cap is user-visible in the report.

## 6. Offline verification

All on this tree, after every change:

- `bash tests/run.sh` → **54 steps, 0 failed**; `luacheck .` → **2 warnings / 0 errors in 97
  files** (the pre-existing pair only: `compat.lua:36` unused `addon_name`, `main.lua:87`
  `table.pack`). No new warning, and the two unused test locals this lane introduced were
  removed rather than silenced.
- Suite counts: `tests/bars_state.lua` 1040 → **1128** checks (PASS, incl. the F2 acceptance pin); `tests/diag_state.lua`
  260 → **294** (PASS); `tests/options_load_state.lua` 3645 → **3743** (PASS);
  `tests/power_bar_state.lua` **190** (unchanged, PASS); `tests/hunter_state.lua` **1909**
  (unchanged, PASS).
- File-scope local budget (`tests/toc_check.lua`): `main.lua` 36, `bars.lua` 42, `diag.lua`
  43, `option_tables.lua` 21, `config_presets.lua` 3, `option_table_presets.lua` 4 — all far
  under the 190 guard.
- **Mutation proofs: 21/21 killed, 0 survived, 0 bad patterns** — run on a throwaway
  `rsync` copy of the tree (`--exclude=Media --exclude=docs --exclude=.git`; the copy also
  passed the full gate before and after the mutations). Each mutation is an exact-text
  replacement in the shipped source, then the owning suite must fail. Every mutated file is
  `luac5.1 -p` clean before the run: the first M1 attempt inserted an early `return` that was
  not the last statement of its block (a Lua syntax error, so the suite aborted at load);
  it was re-run as `do return "kept" end` and the kill is a real assertion:
  "WARRIOR holding the old shipped -166 is re-placed (got kept, want moved)":

| # | mutation | killed by |
|---|---|---|
| M1 | placement rule is a no-op (`do return "kept" end`) | "WARRIOR/ROGUE holding the old shipped -166 is re-placed" (got kept) |
| M2 | shipped-default gate dropped | "a dragged x is a user position (kept)" |
| M3 | latch read loses `rawget` | "OnInitialize latches the class row…" |
| M4 | latch ignored | "never re-evaluates once latched (cannot fight a drag)" |
| M5 | pair height not applied | "the pair height sizes the mainhand in the same pass" |
| M6 | offhand ignores the pair | "the pair height sizes the offhand in the same pass" |
| M7 | band forgets the power slot | "the reserved band reaches through the power-bar slot" |
| M8 | OnInitialize never calls the rule | "OnInitialize latches the class row…" |
| M9 | pair key read without `rawget` | "an unset pair leaves no key behind (no AceDB '**' pollution)" |
| M10 | diag line drops `tick=` | the exact mainhand BAR STATE line |
| M11 | diag ignores `class_hands` | "a one-hand class prints exactly one BAR STATE line" |
| M12 | queue flags on every hand | the exact offhand BAR STATE line |
| M13 | per-hand Height never locks | "the mainhand Height is locked while the pair owns it" |
| M14 | Appearance height routing removed | "editing the mainhand Appearance Height writes the pair key" |
| M15 | offhand Height shows its inert key | "the Positioning offhand Height follows the mainhand" |
| M16 | gate made warrior-only | "ROGUE: combat + target alone never shows the ranged bar" |
| M17 | diag profile row read through the metatable | "the report indexes no missing profile key" |
| M18 | placement moves a non-default x/shipped row | "a dragged x is a user position (kept)" |
| M19 | target ignores the shipped default | "lands on the shipped row a fresh profile gets" |
| M20 | rule reports but never writes | "lands on the shipped row a fresh profile gets" |
| M21 | the one-time placement notice removed | "WARRIOR tells the user once that its saved row moved" (got 1, want 2) |

## 7. Test pins re-cut (and why)

1. `tests/diag_state.lua` — **the verbose line indices and the line count**, because the three
   new BAR STATE lines shift everything after them: 73 → 76 lines (5 base + 3 bars + 67 ids +
   1 errors-none); ids open at line 9 instead of 6; the last wanted id is line 75; the errors
   line is 76; the ids-truncation pins moved from `captured[6..14]` to `captured[9..17]`.
   Mechanical, not behavioural.
2. `tests/diag_state.lua` — the **cap arithmetic** pins: `MAX_LINES = 6` now truncates the
   bar section first (`bars +3 more (cap 6)`, which pins the "never a silent cut" rule
   instead of the ids section); `MAX_LINES = 10` leaves `ids +66 more (cap 10)`. The
   errors-cap test moved from cap 75 to **cap 80** (`5 base + 3 bars + 67 ids = 75` lines
   before the ring, so at cap 80 four of eight entries fit and the count line is
   `errors +4 more (cap 80)`); at the old cap 75 the errors section would now be dropped
   entirely, which would have weakened the test rather than the module.
3. `tests/diag_state.lua` — the default-cap fallback pin 73 → 76 and `MAX_LINES` restore
   values 85 → 88. Same cause.
4. `tests/bars_state.lua` — nothing invalidated; the file only **gained** §12 (placement,
   pair height, rogue parity, the AceDB `rawget` pollution pins). `tests/power_bar_state.lua`
   was NOT re-cut: the first wave's slot rule already puts the power bar where the new
   placement rule reserves it, and the first wave's pins still pass unmodified.
5. New checks (not re-cuts) also live in `tests/options_load_state.lua` §30: widget presence
   per hand set, bounds, placement next to the Height widgets, nil-safety of
   `set(nil, …)`, the reset button, and the getter/setter routing for both the pair and the
   offhand-follows-mainhand rule.

## 8. UNVERIFIED — needs a live client

No in-client session for this lane. Everything above is offline (stubbed frames/engine).
What remains unproven, in the order it matters:

- **U1 — the placement rule on the operator's own profile.** If their rogue/warrior ranged
  hand still holds `-166` and their melee rows are at the shipped `CENTER` anchor, the next
  login moves it to `-98` once. In-client checks: (a) the ranged bar is above the melee stack
  and the power bar is directly under the offhand row; (b) it stays put after a `/reload`
  (the latch) and after dragging it somewhere (the drag wins); (c) `/st diag` shows the
  ranged line's `pos=` as the new row.
- **U2 — the migration's blind spot.** A profile whose melee row was *dragged* (a non-CENTER
  anchor point) or *scaled* is left alone by design: the vertical offset of a non-CENTER
  anchor cannot be derived from SavedVariables, so guessing could move a layout the user
  built. If the operator's own melee bars were dragged, their ranged row will NOT be moved
  and the recovery path is a drag, a profile reset, or a ruling that the rule may assume the
  shipped melee rows.
- **U3 — the melee pair height feel.** The widget sizes both bars in one pass, but only the
  operator can judge whether 6..60 px and the one-pixel step are the right range, and whether
  the pair height should also drive the HUNTER melee stack's row spacing (it does: the stack
  pins MH/OH and keeps each hand's height, so the pair height applies there too).
- **U4 — the honest Height widgets in the tabbed options UI.** Offline we pin the getters,
  setters and `disabled` results, not AceConfig's rendering: that the locked Offhand Height
  actually greys out, that its description reads as intended, and that the Positioning panel
  shows the pair block between the melee and ranged groups.
- **U5 — the new diag lines on a live client.** The format is pinned; what needs eyes is that
  the three lines are readable in the chat frame at the operator's UI scale, that `fill=1.00`
  on an idle hand and the live `progress=` values match what is on screen, and that the
  hunter `queue=` flags flip with a queued Raptor/Steady shot.
- **U6 — Wrath/Cata/Era-specific geometry.** The rule uses the db rows only, so it is
  family-independent; but no client was available to confirm the power bar's rendered slot
  matches the computed band on a family where `power_bar_height` was customized.
- **U7 — carried from the first wave, still open:** the `Always` show option vs the activity
  gate (D1), the hunter_ui frame ownership while the ranged bar is hidden (U5 of
  `bars_decouple`), and the `weave_range` distance bar showing while meleeing is now an
  explicit operator ruling (independent widget; leave it).

## 9. Findings (one is a real defect outside this lane's write scope)

- **F1 — AceDB's `'**'` metatable turns a missing-key READ into a WRITE.**
  `Libs/AceDB-3.0/AceDB-3.0.lua:88-107`: the `__index` of every `'**'`-backed table creates a
  new sub-table, fills it from the defaults, and `rawset`s it on the host table. So
  `profile.anything` on the profile root (or `class_row.anything` on a class row) PERSISTS
  junk in SavedVariables and reads back truthy. This lane's latch and pair-height reads are
  `rawget`-based because of it, and both are pinned (`bars_state` §12a/§12c, `diag_state`
  §11b with a `'**'`-shaped fixture).
- **F2 — `ST.migrate_appearance_defaults` (config.lua) can never run on a live profile.**
  Its first statement is `if profile[ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG] then return 0
  end` (config.lua:162), and `profile` is the live AceDB profile root (option_tables.lua
  passes `get_profile_table()`), which has the `'**'` metatable from
  `ST.defaults.profile['**'] = ST.class_defaults`. That read therefore CREATES a
  defaults-filled table and returns truthy, so the migration returns 0 immediately and the
  2026-10-25 opaque-backdrop default never reached any saved profile. The suite
  (`tests/appearance_defaults_state.lua`) builds plain profile tables, so it cannot see it.
  **Proven, not reasoned:** `tests/bars_state.lua` §12e runs the real migration against the
  real AceDB profile of a booted Warrior holding the old `0.85` backdrop — it raises 0, the
  flag read leaves a created table behind, and the saved alpha is still 0.85. §12e is written
  as an ACCEPTED-KNOWN-DEFECT pin (the house style of `tests/options_load_state.lua` §3): it
  prints the evidence every run and FAILS if the migration starts working, so the acceptance
  is removed together with the fix. **Not fixed here:** `config.lua` is outside this lane's
  write scope and the fix is a one-line `rawget`, ideally plus a `'**'`-shaped fixture in its
  suite. Filed for the orchestrator.
- **F3 — the guide summary in `/st diag` has the same read shape** (`guide_state` reads
  `profile[class]`). Benign on a live profile because all ten class rows are rawset by
  AceDB's copyDefaults at first login; only a class token the addon does not ship could
  create a row. Noted, not changed.
- **F4 — decision taken, not a disagreement:** the placement rule reserves the power-bar row
  even while the power bar is switched off (a row, not a widget). If the operator wants a
  colliding shipped row to be allowed while the power bar is off, that is a one-condition
  change in `melee_reserved_band`.

## 10. Files changed (and deliberately not)

Changed: `main.lua`, `bars.lua`, `config_presets.lua`, `option_tables.lua`,
`option_table_presets.lua`, `diag.lua`, `tests/bars_state.lua`, `tests/diag_state.lua`,
`tests/options_load_state.lua`.

Verified byte-identical to the pre-session baseline (sha256): `power_bar.lua` (`42dcce37…`),
`weave_range.lua` (`480b70e8…`), `hunter_ui.lua` (`7a0fca5d…`),
`tests/power_bar_state.lua` (`23f736bf…`), plus untimed `config.lua`, TOCs,
`CHANGELOG.md`, `README.md`, `.luacheckrc`, `tests/run.sh`, `classes/*` (mtimes predate this
session).

Suggested CHANGELOG bullets for the docs lane (not written here): "The ranged bar is
re-placed above the melee stack for existing profiles (once, at login, and never against a
dragged position); one Melee pair height resizes the mainhand and offhand together and the
per-hand height controls now follow it; `/st diag` prints a per-hand bar-state line so a
silent bar fault is visible." Version stays 2.1.3 until the operator releases.
