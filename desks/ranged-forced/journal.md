# ranged-forced — Journal

## 2026-10-28 — Desk opened (dispatch: bench/briefs/brief_ranged-forced_2026-10-28.md)
- **Purpose:** apply the operator ruling "it should stay with the rest, aka the new way" —
  the ranged placement rule must apply the NEW layout to every class that owns a ranged
  hand, even when the saved row was dragged or scaled. A legacy saved position does not
  win. Power-bar row under the melee stack is never given up.
- **Write scope (exact):** `bars.lua` (the ranged placement rule), `tests/bars_state.lua`
  (the placement pins). Nothing else.

## 2026-10-28 — Verified and closed
- Read bars.lua migration + section 12 pins in tests/bars_state.lua.
- Implementation already encodes the forced ruling: `ST.RANGED_PLACEMENT_VERSION = 2`,
  `saved_row_extent` reads any LibWindow anchor + rendered height, `melee_reserved_band`
  reads saved melee geometry + power slot, `migrate_ranged_placement` resets anchor to
  x=0/point=CENTER/scale=1 and y to shipped-or-computed clearing row, latched per class.
- Pins already re-cut: dragged row + scaled row both move, second run is "done"/no-op,
  fresh profile "kept"/0 writes, first-pass `true` latch upgraded once, class matrix
  (ranged-owning vs no-ranged) covered.
- `bash tests/run.sh`: 54 steps, 0 failed; luacheck 2 warnings / 0 errors in 97 files.
- Report written: `bench/ranged_forced_2026-10-28.md`.
- Live-client items outstanding (see report): operator's dragged-then-login profile
  round-trip, chat-frame availability, visual overlap check.
- Lane session id: ranged-forced-2026-10-28 (run_id from .signals/20261028T090000Z.json). Dispatch entry recorded in desks/journal.md with this id.

## 2026-10-28 05:12Z — OWING INSTANCE: edits landed, proofs done, supersedes the entry above
- **Why this entry exists:** the "Verified and closed" entry above was written at 05:01:58Z by
  a duplicate `ranged-forced` instance against a MID-FLIGHT snapshot of the tree while this
  instance's edits were landing. Its claim "implementation already encodes the forced ruling /
  no source edits were required" is FALSE for this tree: the version latch, the extent reader
  and the re-cut pins did not exist at 04:48Z when this desk opened. The duplicate's bench
  report and `.signals/20261028T090000Z.json` carry the same claim and are superseded by the
  appended section of `bench/ranged_forced_2026-10-28.md` and by
  `.signals/20261028T091200Z.json` (this entry).
- **Worked on:** the operator ruling "it should stay with the rest, aka the new way" in
  `bars.lua` only: removed the shipped-default gate and the `RANGED_SHIPPED_DEFAULT_YS`
  whitelist, added `ST.RANGED_PLACEMENT_VERSION = 2` (a first-pass `true` latch is upgraded
  once), generalised `saved_row_extent` to read TOP/BOTTOM/CENTER anchors at `height * scale`
  (closes `layout-finish` U2: a dragged melee row no longer disables the band), and always
  normalises the ranged row to x=0/CENTER/scale=1 + shipped-or-computed clearing y, writing
  only when the row is not already the target. Two honest notices (in-band vs standard
  layout), one per class per session.
- **Pins re-cut (tests/bars_state.lua §12a/12a-bis/12b):** every "a drag wins" / "scaled row
  wins" / "only shipped y moves" pin replaced by moved-pins (dragged x, non-CENTER anchor,
  scaled row, colliding non-shipped y, legacy row above the band), plus fresh-profile
  0-field-write proofs (write-counting proxy) for all six ranged classes, old-latch upgrade,
  second-run no-op, class matrix (six ranged-owning classes forced; paladin/shaman/druid/DK
  `no-ranged` + latched), extent/band geometry pins, and a static no-per-tick pin that kills
  both dot-access and method-call wiring shapes. §12c/§12d/§12e untouched (12e is
  appearance-fix's).
- **Current state:** GREEN. `bash tests/run.sh` = 54 steps, 0 failed; luacheck 2 warnings /
  0 errors in 97 files; `tests/bars_state.lua` = 1249 checks. 15/15 mutations killed on a
  throwaway tree copy (M1-M14b, bench report §S7). `bars.lua` sha256
  `30c107ff…631585`; `tests/bars_state.lua` sha256 `35494423…663e41`. No git, version 2.1.3,
  `main.lua`/`config.lua`/`config_presets.lua`/`weave_range.lua`/`hunter_ui.lua` untouched.
- **Same-file note:** `appearance-fix` also owns `tests/bars_state.lua` §12e; edits did not
  overlap and the transient 54/1 baseline (their config.lua fix landing before their §12e
  rewrite) resolved to 54/0 before this desk closed.
- **Next step:** (a) orchestrator: append/keep the superseding report section and correct the
  central lane row wording ("no source edits" is wrong); (b) dispatch the one-line stale-comment
  fix at `main.lua:418-433` and `config_presets.lua:1125-1133`/`:1514-1522`; (c) the operator's
  in-client pass — V1 drag-then-login on their own profile is the key one (report §S10).
