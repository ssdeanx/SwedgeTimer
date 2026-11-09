# ui-truth-diag (2026-10-28) — the offhand Width lie closed; /st diag can see the failures that matter

Desk `ui-truth-diag`. Brief: `bench/briefs/brief_ui-truth-diag_2026-10-28.md` (dispatched by the
orchestrator after the independent publish audit's **NOT READY** verdict,
`bench/publish_audit_2026-10-28.md`). Two findings were assigned: **E1** (the offhand Width
slider is inert) and **P4** (`/st diag` cannot see the failures that matter).

Write scope held exactly: `option_tables.lua`, `diag.lua`, `main.lua`, `power_bar.lua`,
`tests/options_load_state.lua`, `tests/diag_state.lua`. Nothing else: no git, no docs, no
TOC / `Libs/` / `.luacheckrc` / `tests/run.sh` / `config.lua` / `bars.lua` / `hunter_ui.lua` /
`classes/*` edits, no version change (2.1.3), LF endings preserved (all six files were and
remain CR-free).

Operator order in force, verbatim: **"off hand should always be same width as main hand."**

Gate after the lane: `bash tests/run.sh` → **54 steps / 0 failed**; `luacheck` **2 warnings /
0 errors in 97 files** (the documented floor: `compat.lua:36 unused addon_name`,
`main.lua:87 table.pack` — both pre-existing, none added by this lane).

## 1. E1 — the offhand Width widget no longer lies

The defect: `option_tables.lua` rendered a per-hand Width range whose setter wrote
`offhand.bar_width`, while `bars.lua:292-321` (`hand_bar_size`) ALWAYS replaces the offhand's
width with the mainhand's on every layout pass (`:309-310`, unless a per-pass override such as
the hunter melee stack is in force). Height had been locked by `layout-finish`; Width had not.
So for every offhand-owning class the slider accepted input and changed nothing.

Fix (`option_tables.lua:7210-7275`), the same treatment the Height widget already has, and
then some — lock + honest read + routed write:

- **show the effective width** — `get()` for `offhand` reads the **mainhand's** `bar_width`
  (`:7238-7248`), i.e. the number the bar actually renders at; mainhand/ranged keep their own
  key.
- **locked** — `disabled()` returns true for the offhand only (`:7270-7274`).
- **short description** — "The offhand always renders at the mainhand's width, so this field
  follows the mainhand." (`:7223-7236`), and the pre-existing hunter-melee-stack sentence is
  kept for every non-ranged hand (the stack overrides both melee hands for the pass).
- **write routed to the key that sizes the bar** — a write aimed at the offhand lands on
  `mainhand.bar_width` and reconfigures the mainhand pass (which cascades to the built
  offhand), so even a programmatic set cannot recreate the lie (`:7249-7269`).

**Sibling offhand size controls checked** (the brief asked):

| control | verdict | evidence |
|---|---|---|
| Positioning → Offhand **Height** | already truthful, still locked; shows the effective height (pair/mainhand) | `option_tables.lua:7276-7343`; `layout-finish` §3; pinned |
| Positioning → Offhand **Width** | **E1, fixed here** | `option_tables.lua:7210-7275` |
| Offhand **Scale** | functional, not inert: per-hand `db.scale` is read by `bars.lua:saved_row_extent (:392)` and applied to the anchor by LibWindow | read of `bars.lua:380-400` |
| Offhand **x/y/Anchor Point** | functional, per-hand LibWindow rows | `option_tables.lua:7345+`; `LWIN.RestorePosition` |
| Offhand **deadzone width** | functional: derived from the hand's EFFECTIVE width (`bars.lua:1643-1686`), not from the inert key | read of `bars.lua:1640-1686` |
| Appearance panel per-hand Width | does not exist (commented out at `option_tables.lua:7555+`), so nothing to lock | read |

No saved key is rewritten by the lock; the offhand's own `bar_width` key is simply no longer
presented as if it sized the bar. This is the honest consequence `layout-finish` already
documented for Height.

## 2. P4 — `/st diag` now surfaces the four named blind spots

### 2.1 A power-bar line (one line, always in the verbose report)

`diag.lua:873-932` (`power_line`), wired at `:1254`. Fields, fixed order:

```
power ready=yes anchor=offhand anchor_shown=yes shown=yes width=275.00 height=14.00
      type=0 token=MANA value=3000/3000 fraction=1.000 why=-
```

- `anchor` is the owning melee **hand** (offhand/mainhand/none) and `anchor_shown` whether that
  row is on screen — this distinguishes "off" from "no anchor" from "anchored to a hidden row".
- `why` names the reason the bar is hidden this tick, from the **same** resolver the driver
  uses (new `power_bar.lua:382-441`, `pb.resolve`, stored in `pb.last_state` at `:443`):
  `no-frame | no-addon | off | no-anchor | no-api | no-type | no-value | no-fraction`;
  `-` while painted.
- `type/token/value/fraction` are the LIVE reading through `st.api.UnitPowerType/UnitPower/
  UnitPowerMax` (the same compat wrappers the bar paints from), rendered `unknown`/`?` when the
  client restricts or cannot answer (secret regime, sandbox). `fraction` reuses
  `pb.fraction`, so the report and the fill maths cannot disagree.
- `module=no` when `st.power_bar` is absent, and `ready=no` when `pb.init` never ran — the
  module is never silently skipped.

`pb.update` now renders from `pb.resolve` (read-only: frames are read, nothing is shown,
hidden or created, and no profile key is written), so `pb.last_state` is a **receipt** written
only by the driver; `diag.lua` only reads it. The previous update gate order is unchanged and
`tests/power_bar_state.lua` (out of this lane's scope) passes untouched (190 checks), including
its "zero power reads while disabled/unanchored" pins.

### 2.2 Per-hand BAR STATE lines: gate + receipt + a reason for `shown=no`

`diag.lua:672-736` (`bar_line`), helpers at `:598-670`. Each hand line now carries, in fixed
order after `built/shown`:

```
why=<token|-> gate=<open|closed|n/a|?> active=<yes/no/?> win=<s|?> left=<s|none|?>
src=<cleu|forever|shot|auto-repeat|none|?>
```

- `gate` is main.lua's own `hand_visibility_needs_activity`/`hand_is_in_use` result (`n/a`
  for the mainhand, which has no activity gate), `win` is `hand_activity_window`, `left` is the
  window remaining (floored at 0.00; `none` with no receipt; `?` when the clock or window is
  unreadable — a receipt with no clock is never rendered as 0).
- `active` is the `has_activity` receipt flag; `src` is the receipt source. main.lua now
  records the writer's token: `"cleu"` (player-sourced offhand SWING_DAMAGE/SWING_MISSED,
  `main.lua:1162`), `"forever"` (Forever engine PLAYER_SWING START, `:1524`), `"shot"`
  (completed ranged shot, `:2206`). A receipt with no recorded source renders `?`, and
  `auto-repeat` is named when only the Auto Shot armed reading keeps the hand in use.
- `why` is the **recorded** reason, written at the point the visibility decision hides the bar
  (`main.lua:2939-2955`, `note_hand_hide_reason`/`hand_disabled_reason`, called from
  `set_bar_visibilities` `:2995-3014`, `handle_bar_visibility` `:2957-2990`, and `show_bar`'s
  druid form / warrior spec branches `:330-370`). Tokens: `unbuilt | class-off | off |
  no-weapon | spec | form | show-rule | idle`; `-` while shown, `?` when nothing was recorded.
  This is the same writer/reader split the module already uses for `diag.tick_sites`, so the
  report cannot drift from what the poll did.

### 2.3 A quarantine line naming every guarded site

`diag.lua:934-999` (`quarantine_line`), wired at `:1258`, one fixed line after the bar block,
sorted quarantined-first then by throw count then site name (deterministic across sessions):

```
quarantine total=31 sites=hud:cs=25[q],practice:tick=4,bars:mainhand:2=2
```

- `sites=none` on a clean session; `sites=?` when the per-site map is unreadable; `total=?`
  when the total is unreadable (never a fake clean zero).
- capped at 8 sites with an explicit `,+N more sites` tail.
- the guard's own total (`bar_hook_errors=<n>`) still prints on main.lua's runtime line;
  nothing was removed.

### 2.4 Cap accounting

Verbose report is now 5 base + 3 bars (class-dependent) + 1 power + 1 quarantine + 67 ids +
≤8 error-ring lines. Worst case **85** lines; `diag.MAX_LINES` stays **88** (headroom kept,
never a silent cut). The sections keep `append_section`'s explicit `+N more (cap N)` tail;
at cap 6 the bar section still closes with `+3 more (cap 6)` (pin kept), and the new fixed
lines are accounted for in the tests.

## 3. Files changed (all six in scope; no others)

| file | sha256 | what |
|---|---|---|
| `option_tables.lua` | `af9692938a1bd6a6398cffe1029f8d546eba7a77157f13b16efdc4086399c32c` | offhand Width locked/honest/routed (`:7210-7275`) |
| `diag.lua` | `17e6d3c7b1a3ef1323f3525c66e0773a558b618704ea0d8a3d70494685adf89a` | power line, gate/receipt/why fields, quarantine line, cap comment |
| `main.lua` | `5184eee394d7cdf5b9818cb9b1462e0fd784a61aa89e24611726657bb6e63085` | receipt source tokens (`:1162/:1524/:2206`, `note_hand_activity` `:2813`), hide-reason recording (`:2939-2955`, call sites `:330-370`, `:2957-3014`) |
| `power_bar.lua` | `929053fddd6cb80289c7db6515d5d37cd012dc53efc52f3332afb31fdcda0a05` | `pb.resolve` (`:382`), `pb.last_state` receipt (`:443`), anchor hand named, header note |
| `tests/options_load_state.lua` | `b639da1afd29e8aeb34efa5fb31071e4f5cce487540f98e45f0d60f4105c7819` | new §31: the truthful offhand Width (get/lock/desc/routing), 4 classes + no-offhand classes |
| `tests/diag_state.lua` | `91819c83b3dc76f05808d4c02f40c8f477ce3b81905bb802297d68ecd1505970` | re-cut line/indices/cap pins + new §11c (power, gate/receipt, quarantine) + wiring pins |

Line counts: `tests/diag_state.lua` **389 checks** (was 294), `tests/options_load_state.lua`
**3821 checks / 0 failed** (was 3750-ish; §31 adds 51), `tests/bars_state.lua` **1249**
(unchanged, untouched), `tests/power_bar_state.lua` **190** (unchanged, untouched).

## 4. Pins re-cut (and why) — tests/diag_state.lua

1. Verbose line count **76 → 78** (`5 base + 3 bars + 1 power + 1 quarantine + 67 ids +
   1 errors-none`); ids open **9 → 11**, last wanted id **75 → 77**, errors line **76 → 78**.
   Cause: two new fixed lines.
2. Empty-state verbose count **76 → 78**; non-numeric-`MAX_LINES` fallback **76 → 78**;
   `no C_Secrets` verbose count **76 → 78**. Same cause.
3. The three **exact BAR STATE lines** (fully populated mainhand, offhand, one-hand class)
   gained `why=- gate=n/a active=? win=? left=none src=none`; the single-hand ids index
   **7 → 9** and that line-count pin **74 → 76**. Cause: the P4 fields + the power line.
4. ids-section indices: first id **9 → 11**, `34428` **16 → 18**, `32216` **17 → 19**. Cause:
   the two new fixed lines.
5. ids truncation pin: `MAX_LINES=10 → "+66 more (cap 10)"` re-cut to `MAX_LINES=13 →
   "+65 more (cap 13)"`, plus a new pin that at cap 10 the fixed block fills the report and
   prints the quarantine line last. Cause: the fixed block is now 10 lines, so cap 10 cannot
   reach the ids at all; the old pin would have measured the quarantine line instead.
6. Errors truncation pin at cap 80: `"+4 more (cap 80)" → "+6 more (cap 80)"`. Cause: 77
   lines now precede the ring (was 75).
7. Hidden-hand pin extended: `shown=no` now also asserts `why=?` (nothing recorded) and then
   `why=idle` with a stamped reason; unbuilt hand asserts `shown=? why=unbuilt`.
8. Static wiring pins added: `note_hand_hide_reason` + its stored field, each hide token wired
   immediately before a `hide_bar(hand)`, the disabled-branch routing, the receipt-source
   tokens, `pb.resolve`/`pb.last_state`, and the power/quarantine builders + their pcall wiring.

**No pin was re-cut in any file outside this lane's scope.** `tests/options_load_state.lua`
had no `bar_width` pin at all (the Width widget was untested — that is how E1 survived), so §31
is new checks, not a re-cut.

## 5. Mutation proofs (16 killed / 16 applied)

Run against the real suites through an in-memory `io.open`/`loadfile` substitution harness (no
tree copies — `/tmp` is being purged by another actor mid-wave), each mutation applied to the
module text the suite loads, then the suite run unmodified:

| # | mutation | result |
|---|---|---|
| M1 | offhand Width `disabled` returns false (lock removed) | KILLED (4 checks) |
| M2 | offhand Width `get` returns its own inert key | KILLED (4) |
| M3 | Width setter writes the offhand key instead of the mainhand | KILLED (8) |
| M14 | offhand Width description no longer says it follows the mainhand | KILLED (4) |
| M18 | hunter-stack sentence dropped from the width description | KILLED (1) |
| M4 | power line dropped from the report | KILLED (17) |
| M5 | bar line `why=` dropped | KILLED (7) |
| M6 | quarantine line dropped | KILLED (7) |
| M7 | `src=` receipt field dropped | KILLED (5) |
| M8 | `gate=` field dropped | KILLED (8) |
| M9 | `left=` window field dropped | KILLED (8) |
| M10 | `win=` field dropped | KILLED (4) |
| M11 | `unbuilt` reason dropped | KILLED (2) |
| M12 | main.lua hide reason not stored | KILLED (2) |
| M13 | main.lua receipt source not stored | KILLED (2) |
| M15 | power_bar `pb.last_state` not stored | KILLED (2) |
| M16 | `idle` token unwired | KILLED (3) |
| M17 | power `why` token table rejects `no-anchor` | KILLED (2) |
| M19 | unknown quarantine total rendered as 0 | KILLED (2) |
| M20 | missing site map claims `sites=none` | KILLED (2) |

(20 mutations run; every one applied and killed. Two first attempts, M14-old and M18-old,
were text mutations that left the pinned phrase intact — re-run decisively and killed; that is
a mutation-quality note, not a surviving mutant.)

## 6. What needs a live client

Offline (stubbed frames, a stubbed power API, no WoW client) cannot prove rendering or chat
readability. In the operator's session:

- **U1 — the locked offhand Width.** AceConfig rendering: the offhand Width greys out, shows
  the mainhand's number, and its description reads as intended; moving the mainhand Width moves
  the offhand bar and the locked field with it. Also check the hunter melee stack case: with the
  stack on, both melee bars follow the ranged width (the description says so).
- **U2 — the power line's truthfulness.** `/st diag` on a class with an offhand: `anchor=offhand`,
  `shown=yes`, `width/height` equal the rendered bar, `fraction` tracks the fill, `type/value`
  match the resource. Then switch the power bar off → `why=off`; disable the offhand hand row
  → `anchor=mainhand`; id on Retail/Mainline secret regime → `type=unknown value=unknown`.
- **U3 — the gate/receipt fields.** A real offhand swing → `gate=open active=yes src=cleu`;
  the Forever client → `src=forever`; a real shot → `src=shot`; ranged armed on Auto Shot with
  no shot yet → `src=auto-repeat`; two cycles after the last receipt → `gate=closed why=idle`
  and `left=0.00`, matching when the bar disappears on screen.
- **U4 — the `why=` tokens.** `off` (hand toggle off), `no-weapon` (offhand emptied),
  `show-rule` (out of combat/target), `idle` (gated), `form` (druid non-bar form),
  `spec` (warrior tank/arms hide), `class-off` (class master switch off). Each is recorded
  where the hide happens; a live read confirms the label matches what the operator did.
- **U5 — the quarantine line.** A clean login must print `quarantine total=0 sites=none`; a real
  throwing site is hard to force, but the format/sort/cap are pinned offline.
- **U6 — chat readability.** The bar lines are now longer (~230 chars at the widest); confirm
  they still wrap readably in the operator's chat frame at their UI scale.

## 7. Residuals and cross-lane observations (not fixed, outside this lane)

- **A behavioral pin for main.lua's hide-reason recording belongs in `tests/bars_state.lua`**
  (that suite already drives the real visibility poll; this lane may not edit it). Here the
  recording is pinned statically (function, stored field, every token wired before a
  `hide_bar`), and its rendering is pinned behaviorally with a stamped reason. If a later pass
  wants the full loop covered, add a `state.hide_reason` assertion there — file it with that
  file's owner.
- **Transient cross-lane state, observed once and now settled:** while `hunter_ui.lua` was
  mid-write by the other lane (06:13 local), `tests/bars_state.lua` failed 15 hunter checks
  including `HUNTER: exactly the documented frames were created (got 21, want 20)` — one extra
  hunter-owned frame. The settled tree passes (1249 checks). If the final hunter_ui keeps that
  extra frame, `tests/bars_state.lua:992` (`extra_frames = 6`) needs a re-cut by its owner; it
  is in neither this lane's nor (apparently) the other lane's write scope.
- **luacheck transient:** one mid-wave run showed 4 warnings (2 from `tests/hunter_state.lua`
  while the other lane was writing it). The settled tree is back to the documented 2/0 in 97
  files. This lane added no warning.
- **No behavior change to the activity gate itself** (HU-38 D1 open): `Always` still cannot
  surface an idle offhand/ranged hand. The diag now *says so* (`gate=closed why=idle`) instead
  of leaving it invisible.

## 8. Trail

- Desk: `desks/ui-truth-diag/` (journal + `.signals/`).
- Gate: `bash tests/run.sh` 54/0; luacheck 2/0 in 97 files — re-run after the last edit.
- Version 2.1.3 untouched; no git; no docs; no TOC/Libs/`.luacheckrc`/`tests/run.sh` edits;
  line endings LF in all six files.
