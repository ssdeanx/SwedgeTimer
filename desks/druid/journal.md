# druid — Journal

## 2026-10-17 — Desk opened
- **Purpose:** D2 name-based Tiger's Fury / D3 wiring / D4 EMA-smoothed TTD / D5 / D6 + Omen display + tick overlay.
- **Scope:** classes/druid.lua, druid_energy.lua, druid_guide.lua only.
- **Next step:** wait for dispatch brief in bench/briefs/; D1 stays blocked (offline probe dishonest); druid_guide_state checks must not weaken.

## 2026-10-17 — [signal:done] Build-out round 1 complete (offline-verified)
- **Worked on:** D2 TF/Berserk HUD slots (name-based lookups; rank table gains 50213;
  per-family liveness probes; ready-in-combat glow; off-GCD swipe skip), D3 pips wired
  to the installed `ST:new_pips` (bars-design buildout landed mid-lane — probe pruned to
  the confirmed colon path; opts point/x/y + `design` key/title; save seam deferred),
  D4 EMA-smoothed TTD (`TTD_EMA_ALPHA = 0.25`, 0.25 s sampler, heal/death/target-switch
  resets) feeding the frozen `inputs.time_to_die`, D5 "Shred in Xs" countdown (TBC/WRATH
  cost gates), D6 Maul-efficiency badge (at-cap seconds + capped-gain events per fight,
  no rage-unit claims), Omen proc glow (guarded 16870; scan gate extended) and the GCD
  tick overlay on the energy column. All new toggles nil-safe, nil = off. D1 untouched
  (still BLOCKED).
- **Current state:** `tests/druid_energy_state.lua` 136, `tests/druid_state.lua` 415,
  `tests/druid_guide_state.lua` 65757 — all PASS (guide suite grew, never weakened).
  luacheck 0 errors. Full harness 35 steps / 2 failed, both shared-suite descriptor
  rows for the reconcile pass: `hud_state` §15 druid (8→10 slots, +tf/berserk before
  trinkets, icons 10, width 302) and `bars_state` DRUID count row (frames 7 / textures
  21 / fontstrings 9) — exact numbers in `bench/buildout_druid_2026-10-17.md` §6.
  Mutation proofs on `/tmp/opencode/mut_druid/` (final tree): EMA constant → 2 suite
  failures; berserk Era gate → 1 failure; restored, green, copy removed.
- **Next step:** reconcile pass updates `hud_state`/`bars_state` rows + options pass adds
  the §5 toggle keys (recommended defaults documented); in-client check owns every
  visual (pips, countdown text, badge, omen halo, marker).

## 2026-10-19 — [signal:done] Druid feral HUD styles sweep (read-only research lane)
- **Worked on:** wago.io feral sweep (TBC + Era/SoD only): 9 waited scrapes + websearch discovery + 3 screenshots VIEWED. Wrote NEW bench/druid_styles_2026-10-19.md (only new file; glob-verified absent first).
- **Current state:** 7 ranked cards (Sabimaru SoD 38★/358 installs, Ryecoke TBC 9★/159, Meatslab SoD 11★/142, Luxthos Era, Cat-Rotation TBC triggers, Igosha TBC-Anniversary restoration, Grillitassu title-only) + shortlist + per-attempt evidence log. Firecrawl bodies kept minimal per discipline; agent/search rejections recorded with SearXNG fallback noted.
- **Next step:** orchestrator validation; in-client side-by-side owns all pixel geometry (UNCONFIRMED throughout).
