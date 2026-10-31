# hunter-tint — Journal

## 2026-10-28 — Desk opened
- **Purpose:** Fix the hunter main-hand fill recolouring during ranged play. The Raptor
  Strike / Steady Shot queue tint may only apply while the main-hand has a live melee
  swing cycle, and every clear path must repaint immediately so no stale tint survives.
- **Scope:** `classes/hunter.lua`, `hunter_ui.lua`, `tests/hunter_state.lua` (write scope
  held exactly; `main.lua`, `bars.lua`, `power_bar.lua`, `config_presets.lua` belong to the
  parallel `bars-decouple` lane).
- **Brief:** `bench/briefs/brief_hunter-tint_2026-10-28.md` (authoritative).
- **Client context:** operator on TBC Anniversary + Classic Era; no in-client session for
  this lane — offline gate only, state that.
- **Next step:** read the tree (bench lessons/journals first, then the three scoped files),
  reproduce the stale-tint lifecycle offline, land the gate + repaint, re-run
  `bash tests/run.sh`, write `bench/hunter_tint_2026-10-28.md`, journal + done signal.

## 2026-10-28 — Lane complete: tint gated on a live melee cycle, every clear repaints
- **Worked on:** the operator's "why is mh changing colors for hunter when using ranged"
  report. Re-verified the colour path: the only MH fill writer is `ST.HUNTER.set_bar_color`;
  the Raptor/Steady queue flags were set from `IsCurrentSpell` probes and several clear paths
  (combat exit, current-spell clear) dropped the flag without repainting, so a tint could
  survive into ranged play. Landed: a live-melee-cycle predicate
  (`classes/hunter.lua:154-181`), the `set_bar_color` gate + swing-consumed clear
  (`:1414-1470`), combat-exit repaint behind the init guard (`:1384-1400`), repaint on the
  current-spell clear branches (`:1136-1145`, `:1170-1178`), and a per-frame
  `maintain_queue_tint` safety net ahead of the hand gate (`:1240-1268`, called `:1289`)
  covering cycle-gone and target-change. Defaults untouched (raptor ON, steady OFF).
  `hunter_ui.lua` verified unchanged.
- **Tests:** `tests/hunter_state.lua` re-cut (1909 checks, PASS): tint matrices armed with a
  live cycle, clear paths now expect a repaint, new §10c proves B1/B2/B3/B4. 7/7 mutations
  killed on `/tmp` copies. Cross-file pin in `tests/bars_state.lua` (bars-decouple's file)
  was filed, not edited; the owner landed the equivalent re-cut. Final gate: 54 steps /
  0 failed, luacheck 2 warnings / 0 errors in 97 files.
- **Current state:** DONE offline. Report on the bench at
  `bench/hunter_tint_2026-10-28.md`. No in-client session — the trigger cause, the
  `UnitGUID` reading, the tick's visibility coverage and the visible behaviour remain
  UNVERIFIED (listed in report §6). No shipped default flipped; the "keep the Raptor tint ON
  now that it is melee-gated" question is left as an operator decision (report §7).
- **Next step:** in-client pass on TBC Anniversary (and Era): with only ranged shots, watch
  the MH fill stay the default colour; in melee, queue Raptor Strike and confirm the red tint
  appears and clears on the consuming swing; swap targets mid-queue and confirm the clear.
  If the tint still appears at range, capture `/run print(ST.raptor_strike_queued)` and
  `/st diag` — that would mean the flag is set by a path this lane did not model.

## 2026-10-28 — [signal:done] hunter-tint lane complete
- `desks/hunter-tint/.signals/2026-10-28T072953Z.json` — execution/done, run_id
  `hunter-tint-2026-10-28`. Artifacts: `bench/hunter_tint_2026-10-28.md`, the class fix and
  the re-cut `tests/hunter_state.lua`. Gate 54/0; no in-client proof (report §6).
