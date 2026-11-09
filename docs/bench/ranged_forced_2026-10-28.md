# ranged-forced — 2026-10-28 report

Desk: `desks/ranged-forced/`
Brief: `bench/briefs/brief_ranged-forced_2026-10-28.md`
Write scope: `bars.lua`, `tests/bars_state.lua`

## Outcome

Implementation and pins are in place and `bash tests/run.sh` is green (54 steps, 0 failed;
luacheck 2 warnings / 0 errors in 97 files). No source edits were required this pass —
the forced-placement rule (`ST:migrate_ranged_placement`, `ST.RANGED_PLACEMENT_VERSION = 2`)
and its pins already encode the operator ruling "it should stay with the rest, aka the new
way". This report closes the lane.

## What the rule does (bars.lua)

- `ST.RANGED_PLACEMENT_FLAG = "ranged_placement_213"`, `ST.RANGED_PLACEMENT_VERSION = 2`.
  A profile latched at the first pass's `true` is re-evaluated exactly once, then latched
  at `2`; a profile already at `2` is never touched again.
- `ST:saved_row_extent(hand)` reads a row's vertical extent from its OWN saved LibWindow
  anchor (TOP/BOTTOM/CENTER) and at its RENDERED height (height * scale), so a dragged
  anchor and a scaled row are read at their real size instead of being refused.
- `ST:melee_reserved_band()` computes the band from every owned non-ranged hand's SAVED
  geometry, plus the power-bar slot hanging one gap + clamped power height under the
  bottom-most row. A dragged/scaled melee row still yields a band.
- `ST:migrate_ranged_placement(profile)` normalises the ranged row for EVERY class that
  owns a ranged hand:
  - anchor becomes x=0, point=CENTER, scale=1 (the shipped LibWindow anchor);
  - y becomes the class's shipped ranged row when it clears the band by the gap, else the
    lowest integer y that clears it (ceil of band_top + gap + half the ranged height);
  - write only when the row is not already exactly the target row (fresh profiles are
    untouched — no double-write);
  - per-class profile latch makes it once-per-profile: no per-tick work, no geometry
    hopping, at most one notice per class per session;
  - a drag made AFTER the pass is never fought (latch short-circuits to "done").
- Classes with no ranged hand (paladin, shaman, druid, deathknight) answer "no-ranged" and
  still latch.

## Pins re-cut (tests/bars_state.lua, section 12)

The old "a drag wins" / "a scaled row wins" / "shipped-default-only" pins were replaced
by pins that prove the forced behaviour:

- extent reader: CENTER/TOP/BOTTOM anchors, scaled rows (height*scale), missing/garbage
  scale -> 1, unreadable rows -> nil.
- band: dragged and scaled melee rows still yield the band; unreadable melee row -> nil.
- fresh profile: "kept", 0 field writes, no notice.
- old shipped -166 row (warrior, rogue): "moved" to -98, one notice naming "ranged bar
  was moved"; second run "done", 0 writes, no notice, later drag untouched.
- dragged row (x=320, TOPLEFT): moved, x/point/y reset.
- scaled row (scale=1.6): moved, scale reset to 1.
- legacy row above the band (-60, x=-420): moved to shipped row, notice says "placed in
  the standard layout", does not blame the power bar.
- colliding non-shipped y (-170): moved.
- hunter (-166 and dragged): moved to its own shipped row (-120).
- first-pass latch (`true`): re-evaluated once under the ruling, then latched at 2; a
  later drag is left alone.
- class matrix: every ranged-owning class (warrior, rogue, hunter, mage, priest, warlock)
  has a dragged row forced into the new layout; every non-ranged class (paladin, shaman,
  druid, deathknight) answers "no-ranged" and still latches.
- colliding shipped default (-150): moved to the computed clearing row (-100), with the
  2 px gap preserved.
- F2 positive pin (12e): appearance migration runs on a live AceDB profile (owned by the
  appearance-fix lane; verified untouched here).
- static wiring: main.lua calls migrate_ranged_placement, pcall'd.

## What still needs a live client

- The operator's own dragged-then-login profile: the code path is exercised offline (the
  `true`-latch upgrade case and the dragged-row case), but the actual AceDB round-trip on
  the operator's saved profile (dragged anchor + scale + a stale first-pass latch) is the
  key live check. Expected: one notice on first login after update, row lands above the
  melee stack + power bar, no repeat on subsequent logins, and a drag made after the pass
  is preserved.
- Chat-frame availability: the notice is pcall'd through utils.print_msg; a broken/missing
  chat frame must not undo the placement (unverified in client).
- Visual confirmation that the ranged row never overlaps the power-bar slot after migration
  on every ranged-owning class, including hunter's melee stack under the ranged bar.

---

# SUPERSEDING REPORT — appended by desk `ranged-forced`, 2026-10-28T05:12Z

**Correction first.** The Outcome section above ("No source edits were required this pass",
"already encode the operator ruling") was written at 05:01:58Z against a **mid-flight
snapshot** of this tree by a duplicate `ranged-forced` instance, while the owning instance's
edits were still landing. Source edits WERE made, inside this lane's write scope. Everything
above is superseded for the outcome/verification claims and kept as history; the record below
is what the tree now contains. (The duplicate instance's desk journal and `.signals/` done
signal carry the same mid-flight claim; the journal has been appended and a superseding done
signal emitted alongside this report.)

Operator ruling implemented, verbatim: **"it should stay with the rest, aka the new way."**
That closes the `layout-finish` lane's U2 blind spot: the ranged row is placed in the NEW
layout for every class that owns a ranged hand, **even when the saved row was dragged or
scaled**. A legacy saved position does not win; the power-bar row directly under the melee
stack is never given up. Write scope held exactly: `bars.lua` + `tests/bars_state.lua`. No git,
no docs, no TOCs/`Libs/`; version stays 2.1.3.

## S1. Verdict

DONE (offline). The drag/scaled skip is gone, the rule is forced for all six ranged-owning
classes, it stays a single login-time pass (version latch), and the fresh-profile path is
proven to write **zero** fields. 15/15 mutations killed. **The drag-then-login behaviour on the
operator's own profile is UNVERIFIED without a live client** (§S7).

## S2. What changed, and what was removed

`bars.lua:323-588` (the placement policy block) is rewritten around the ruling.

- **REMOVED: the "shipped default only" gate.** The old `is_shipped` predicate (`x=0`,
  `point="CENTER"`, `scale=1`, `y` in `RANGED_SHIPPED_DEFAULT_YS`) returned `"kept"` for any
  dragged/scaled row before the band was even looked at. `ST.RANGED_SHIPPED_DEFAULT_YS` is
  deleted with it — after the ruling there is no saved y that is a reason to keep.
- **REMOVED: the intersection gate as the trigger.** A row no longer has to overlap the band
  to be re-placed; the new layout is the target for every legacy row.
- **ADDED: the version latch** (`ST.RANGED_PLACEMENT_VERSION = 2`, `bars.lua:362`). The first
  pass wrote `true`; a truthy read would make the new rule dead on exactly the profile the
  ruling is about. The rule now takes `rawget(class_row, FLAG) == 2`: `true` (first pass) or
  nil is evaluated **once more**, then latched at 2. Any other stored value is evaluated once.
- **KEPT: the band** = the melee stack's saved extent + the power-bar slot
  (`melee_reserved_band`, `bars.lua:416`), the class's shipped row as preferred target, the
  2 px gap, the per-class latch, the single chat notice, the `rawget` latch read.
- **KEPT: `row_intersects_band`** — it no longer gates the move, but it selects the notice's
  reason: a row inside the reserved band was occupying the power-bar slot; a row outside it
  is a legacy drag/scale being normalised.

## S3. The rule as shipped (`ST:migrate_ranged_placement`, `bars.lua:507-588`)

Returns `"moved" | "kept" | "done" | "no-ranged" | "unknown"`; runs once from
`main.lua:428-433` (unchanged), after AceDB exists and before any frame/options table.

1. Guard profile/defaults/class row (unsupported class ⇒ `"unknown"`, no phantom row).
2. `rawget` the latch; `== ST.RANGED_PLACEMENT_VERSION` ⇒ `"done"`.
3. Write the latch (before the geometry read: every outcome is evaluated at most once).
4. No ranged hand ⇒ `"no-ranged"` (hand set, never a class name: paladin/shaman/druid/DK).
5. `rawget(class_row, "ranged")` (a plain read would let AceDB's `'**'` metatable create and
   persist a defaults table — the trap the latch already avoids).
6. Target: `minimum = band_top + RANGED_PLACEMENT_GAP + ranged_height/2`; the class's shipped
   ranged y when `shipped_y >= minimum`, else `math.ceil(minimum)`.
7. Already exactly `(x=0, y=target, point="CENTER", scale=1)` ⇒ `"kept"`; **no write, no
   notice** (fresh profiles and already-migrated profiles).
8. Otherwise write all four fields (dragged x, foreign anchor and scale are replaced, not
   preserved), then announce once through `st.utils.print_msg` (pcall'd), in-band or
   standard-layout wording.

No per-tick path exists: the rule is named in `bars.lua`'s code exactly once, at its
definition (`tests/bars_state.lua:3752-3778`), pinned for both dot-access and method-call
shapes.

## S4. The band reads a dragged melee anchor and a scaled row (closes U2)

`ST:saved_row_extent` (`bars.lua:381`) no longer refuses non-CENTER anchors/scales. It derives
the extent from **LibWindow's own save contract** (`Libs/LibWindow-1.1/…:140-230`):
`SavePosition` stores the offset of the anchored edge from the same edge of the parent (the
anchor frame is parented to `UIParent`) and `RestorePosition` divides by the frame's scale, so:

- `TOP*` row's saved `y` **is** its top edge → `[y, y - h*scale]`;
- `BOTTOM*` row's saved `y` is its bottom edge → `[y + h*scale, y]`;
- `CENTER`/`LEFT`/`RIGHT` store the vertical centre → `[y + h*scale/2, y - h*scale/2]`;
- rendered row height = `hand_bar_size(hand) * scale`; a missing/garbage scale restores at the
  frame's own 1 (LibWindow's branch), so it reads as 1;
- `nil` now only means "row unreadable" (no y, no positive height).

So a **dragged melee row no longer disables the rule**: the ranged row is still placed above
the real stack. Pinned with a dragged melee anchor (band top stays −110) and a scaled melee row
(band top rises to −85). This is the U2 hole the ruling closed.

## S5. Per-class geometry (fresh rows all already clear the band)

| class | hands | melee rows (y/h) | band `[bottom, top]` | shipped ranged y | fresh outcome |
|---|---|---|---|---|---|
| WARRIOR | MH, OH, ranged | −120/20, −142/20 | [−168, −110] | −98 | kept |
| ROGUE | MH, OH, ranged | −120/20, −142/20 | [−168, −110] | −98 | kept |
| HUNTER | MH, OH, ranged | −142/14, −158/14 | [−181, −135] | −120 (shared) | kept |
| MAGE | MH, ranged | −142/20 | [−168, −132] | −120 (shared) | kept |
| PRIEST | MH, ranged | −142/20 | [−168, −132] | −120 (shared) | kept |
| WARLOCK | MH, ranged | −142/20 | [−168, −132] | −120 (shared) | kept |
| PALADIN / SHAMAN / DRUID / DEATHKNIGHT | no ranged hand | — | — | — | `no-ranged` |

`power_height` is the class's clamped `power_bar_height` via `power_bar.height_for` (14 px
default, 10..30); `gap` is `power_bar.GAP` (2 px) — a customised power bar is honoured. Fresh
pins for **all six** ranged classes assert `kept` and **0 field writes**.

A profile whose *shipped* row itself sits in the band (pinned by moving the warrior default to
−150) lands on the computed row `ceil(−110 + 2 + 7.5) = −100`, 2 px gap preserved.

## S6. Pins re-cut (every one, and why) — `tests/bars_state.lua` §12

| old pin | new pin | why |
|---|---|---|
| §12a `ranged_placement_213 == true` | `== ST.RANGED_PLACEMENT_VERSION` (2) | latch is now a version, so the weaker pass is upgraded once |
| §12b "WARRIOR/ROGUE latch == true after a move" | version 2 | same |
| §12b "a dragged x is a user position (kept)" | **dragged row is `moved`**: x→0, point→CENTER, y→−98, one notice | R4: a drag no longer wins |
| §12b "a colliding y that was never shipped is kept" | **`moved`** to the shipped row | saved-y whitelist gone |
| §12b "a non-CENTER anchor is a user layout (kept)" | **`moved`**, anchor reset | same |
| §12b "a scaled row is a user layout (kept)" | **`moved`**, scale reset to 1 | same |
| §12b paladin+druid `no-ranged` only | class matrix: WARRIOR/ROGUE/HUNTER/MAGE/PRIEST/WARLOCK each forced (dragged+scaled→new layout) **and** fresh-kept with 0 writes; PALADIN/SHAMAN/DRUID/DEATHKNIGHT `no-ranged` + latch | R1/R3/R5 by the hand set, incl. shaman and DK |
| §12b "a colliding shipped default still moves the row" | same + the computed row keeps the 2 px gap (old check was trivially true) | gap is a requirement |
| §12a (none) | 12a-bis: CENTER/TOP/BOTTOM anchors, scaled row, missing/garbage scale, unreadable y/height, dragged+scaled melee bands | closes U2 with proof |
| §12 static wiring (name found in main.lua) | same + name appears **once** in bars.lua's code (comments stripped) | R2 no-per-tick work |
| — | old-latch upgrade: `true` + dragged/scaled row ⇒ `moved` once, latch 2, then `done` | the operator's own profile case |
| — | second run after a move: `done`, 0 writes, 0 prints, later row untouched | R2 once placed |
| — | out-of-band legacy row ⇒ `moved`, standard-layout notice (never names the power bar) | R1 normalisation + honest notice |

§12c (melee pair height), §12d (rogue==warrior gate), §12e (appearance F2) untouched.

## S7. Mutation proofs — 15/15 killed

Throwaway tree copy (`rsync --exclude=Media/docs/.git/bench/desks`); each mutation applied to
`bars.lua`, then `lua5.1 tests/bars_state.lua` on the copy (base: PASS 1249 checks).

| id | mutation | result | fails |
|---|---|---|---|
| M1 | forced reset keeps a legacy anchor/scale (only y moves) | KILLED | 26 |
| M2 | the superseded drag-wins skip returns | KILLED | 52 |
| M3 | latch read truthily instead of by version | KILLED | 8 |
| M4 | "already the target row" guard dropped (always writes) | KILLED | 16 |
| M5 | latch stores `true`, not the version | KILLED | 27 |
| M6 | extent ignores the row scale | KILLED | 4 |
| M7 | extent ignores the anchor point | KILLED | 6 |
| M8 | class's shipped row never used (always computed) | KILLED | 19 |
| M9 | silent move (no notice) | KILLED | 9 |
| M10 | announces on a kept row too | KILLED | 2 |
| M11 | power slot not reserved in the band | KILLED | 8 |
| M12 | class-name gate instead of the hand set | KILLED | 19 |
| M13 | one notice wording for both reasons | KILLED | 3 |
| M14a | per-tick call wired (dot access, `self.name`) | KILLED | 2 |
| M14b | per-tick call wired (method call, `self:name`) | KILLED | 2 |

M14 earned its keep: the first form of the static pin only searched `self:migrate_ranged_placement`,
so M14a **survived**; the pin was re-cut to strip whole-line comments and count every code
mention, and both shapes now die.

## S8. Files changed (this instance)

| file | sha256 after | notes |
|---|---|---|
| `bars.lua` | `30c107ffe3742a07e3a06d6298a8999dbee482be1637eb2366e7482c0e631585` | placement policy only; 42 locals (limit 190); LF preserved |
| `tests/bars_state.lua` | `354944237588147a5758299dad29a26b5e0eab3884ad110239326e0533663e41` | §12a/12a-bis/12b + static pin; 1249 checks |

Untouched: `main.lua`, `power_bar.lua`, `config_presets.lua`, `config.lua`, `hunter_ui.lua`,
`weave_range.lua`, `classes/*`, all 7 TOCs, `Libs/`. Version 2.1.3.

**Same-file coordination:** `appearance-fix` also owns `tests/bars_state.lua` §12e. At 04:51
that lane's `config.lua` fix landed while §12e was still an accepted-known-defect pin, so the
baseline gate was transiently **54/1**; this lane kept off §12e entirely, and by 05:00
`appearance-fix` had rewritten it as "F2 FIXED" and the gate returned to 54/0. The tree now
carries both lanes' edits in one file, non-overlapping.

## S9. Out of scope but now STALE — needs a follow-up edit

Comments that still describe the removed "a drag wins" rule (outside this lane's write scope):

- `main.lua:418-433` — "only while it is still a shipped default and only when it
  demonstrably intersects the melee/power band - then latches; a dragged position is never
  fought."
- `config_presets.lua:1125-1133` (rogue ranged block) and `:1514-1522` (warrior ranged
  block) — "shipped default only, colliding rows only, latched once per profile, so a
  position the user has dragged is never touched."

One-line wording fix each, no behaviour change. No other module references the rule or its
constants (grep over `*.lua`, excluding `docs/`).

## S10. UNVERIFIED — needs a live client (ordered by risk)

- **V1 — drag-then-login on the operator's own profile (THE key one).** Two scenarios: (a) the
  profile already ran today's weaker pass (latch `true`) with a dragged/scaled row; (b) it
  never ran it (no latch). Both must move the row once and print **one** line on the next
  login: ranged bar above the melee stack, power bar directly under the offhand row.
- **V2 — no second pass.** `/reload` after V1: no notice, no move; drag the ranged bar and
  `/reload` again: it stays where dragged (the post-pass drag wins, as the notice says).
- **V3 — the two notice strings** must read sensibly in the chat frame at the operator's UI
  scale (one names the power bar, one says "standard layout").
- **V4 — the rendered power-bar slot per family.** The band is db geometry + clamped height;
  the rendered bar is anchored to the offhand frame. Offline they agree by construction; no
  client was available for Era/TBC/Wrath/Titanforge with a customised `power_bar_height`, or
  for the hunter melee stack (which pins MH/OH under the ranged bar frame — the moved ranged
  row drags the stack with it, expected, unobserved).
- **V5 — residual by design:** `melee_bar_height` applied live *after* the one-shot pass can
  put the ranged row back inside the taller melee band until the user drags it. Re-running on
  every option change would be geometry hopping, which the brief forbids; noted for the
  options/docs pass.
- **V6 — first-login ordering:** the notice is emitted before the options table and first
  frame exist and is pcall'd; confirm in-client that it appears once and cannot abort login.

## S11. Gate

`lua5.1 tests/bars_state.lua` PASS (1249 checks); `bash tests/run.sh` **54 steps, 0 failed**;
`luacheck .` **2 warnings / 0 errors in 97 files** (the pre-existing pair; `luacheck bars.lua`
alone is clean). No git, no version bump, no TOC/Libs/docs edits.

