# corpus-corrections — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Correct the bench corpus where the five utility-layer lanes (warrior,
  hunter, rogue, druid, shaman) proved it wrong, so no future lane inherits the
  errors. READ-ONLY across the addon tree; `bench/*.md` only.
- **Scope:** `bench/rotation_gap_vs_apl_2026-10-20.md` plus the corpus files it
  seeded (`bench/class_features_drills_2026-10-19.md`,
  `bench/ids_research_2026-10-19.md`, `bench/*_rotation_audit_*.md`,
  `bench/perclass_*`). Evidence comes from the seven utility-lane build artifacts
  (2026-10-20) and, where needed, `/home/sam/wow-ui-source`.
- **Next step:** read the gap file section by section, apply the lanes' proven
  corrections with dated correction notes, then sweep the rest of the corpus for
  the same class of error.

## 2026-10-20 — [signal:done] Bench corpus corrected (31 corrections in the seed file, 17 corpus files touched)
- **Worked on:** read the gap file plus the seven utility-lane build artifacts;
  applied every id the lanes disproved, in place, with a dated
  **SUPERSEDED 2026-10-20** marker and a §0.0 correction log (old value /
  corrected value / evidence) in `bench/rotation_gap_vs_apl_2026-10-20.md`; added
  §9 there (the summary of what changed). Then swept the rest of the corpus for
  the same class of error and added dated correction notes to 16 more bench
  files.
- **Corrections applied (30 in the seed file):** shaman 17364 = Stormstrike (no
  Nature's Wrath in any wowsims shaman sim), 29228 = Flame Shock r6, 49231 =
  Earth Shock (49236 = Frost Shock), 10497 = Mana Spring r4, 8512 = the Windfury
  rank-1 fallback; rogue 1857 = Vanish r2 (TBC/Forever), 14183 = Premeditation
  (incl. Forever), 1241584 = Mutilate r4, the Era/TBC APLs carry no Vanish row,
  26867 = Rupture (not Deadly Poison), 51662 = Hunger for Blood (not Mutilate),
  1310703 = Venom, 1259799 = "Elune's Light", 1259812 = "Gnome Eureka",
  14278 = Ghostly Strike; druid 9850 = Claw r5 on Era/TBC/Forever (the Forever
  has no Mangle and no `mangleNow`), the Era APL's [1] row casts 13494 = "Haste"
  (the client's Leader of the Pack is 17007), the Era APL has no Rip row; hunter
  WRATH kill_shot 61006, explosive 60053, TBC steady 34120 (56641 does not
  exist on TBC), the Forever client has no Steady Shot, 61847 = Aspect of the
  Dragonhawk, 25296 = Aspect of the Hawk, the Forever Hawk is a pre-pull row,
  the SoD Kill Shot is the rune 409593, the Era APL has no Arcane Shot row;
  warrior the Sweeping Strikes id is 12723 (12292 = Death Wish on TBC /
  Sweeping Strikes on Forever), 33697 = Blood Fury rank 2, 18499 = Berserker
  Rage, 25212 = the TBC Hamstring (not Devastate).
- **Extra find (not one of the five lanes' named corrections):** the corpus's
  TBC rogue **Sinister Strike / Hemorrhage pairing was swapped** (26862 = SS,
  26864 = Hemorrhage) — `bench/filed_closure_sweep_2026-10-19.md` §9-N1 had
  found it on 2026-10-19 and it was never fixed. Fixed in the three places N1
  named (`class_features_drills` R-03, `rogue_rotation_audit` §1,
  `ids_research` U10).
- **Current state:** the corpus carries no other known-wrong id the lanes named.
  17 bench files carry dated correction notes; the seed file
  (`bench/rotation_gap_vs_apl_2026-10-20.md`) carries the full log (§0.0) and
  the summary (§9). **No `.lua`, no test file, no `desks/` file other than this
  desk's, no `hands-up.md`, no git.**
- **Not corrected, on purpose:** §6 (the paladin) of the gap file — the paladin
  utility lane has not run, so its ids stand as written, and the gap file says
  so. The client-side proof for every Forever id remains owed (the correction
  settles the *name*, not the client source).
- **Next step:** the orchestrator validates. If the operator wants the
  paladin section re-verified too, that is a paladin-APL lane, not this desk.

## 2026-10-20 — [signal:done] corpus corrected
- Emitted `desks/corpus-corrections/.signals/2026-10-20T04-20-00Z.json`
  (`execution` / `done`, run_id `corpus-corrections-2026-10-20`). Artifacts on
  the bench: `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 (the 31-correction
  log) and §9 (the summary), plus 16 further bench files carrying dated
  correction notes. **Validation owner: the orchestrator.**
