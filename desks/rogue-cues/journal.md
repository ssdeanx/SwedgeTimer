# rogue-cues — Journal

## 2026-10-19 — Desk opened (Round 2, brief_rogue-cues-provider_2026-10-19)
- **Purpose:** writer lane for Slice B (tick + Era cue) + Slice C (provider/HUD-live) + TTD wiring.
- **Scope:** ONLY `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua`,
  `tests/rogue_guide_state.lua`, `tests/guide_contract.lua`. OUT: practice.lua, option_tables.lua,
  diag.lua, TOCs, main.lua, bars.lua, compat.lua (parallel practice lane is file-disjoint).
- **Next step:** bench-read (journal, rogue_readiness §§2/4/5-B/C, both fix buildouts/journals,
  both rogue research files, lessons, hands-up), then implement + validate.

## 2026-10-19 — Lane complete (Round 2 cues + provider + TTD)
- **Worked on:** per `bench/briefs/brief_rogue-cues-provider_2026-10-19.md`, only the five scoped files.
  - `classes/rogue.lua` (CRLF kept): proc-aware 2 s tick predictor (seed on +20 in phase; Combat
    Potency 15 / Relentless 25 never re-anchor; out-of-phase or unknown grants and missed ticks
    latch unknown -> nil/hidden, H4; cap phase advances arithmetically); tick spark + pooling wash
    (bands data-driven from `rogue_guide.POOL_BANDS` with db overrides; RETAIL has none);
    Era-only post-MH SS window (exact `ERA` + confirmed sword mainhand from `GetItemInfo`, else
    hidden); weapon-swap band + `"swap: GCD + swing reset"` copy (ERA/TBC/FOREVER; WRATH per the
    recorded conflict, RETAIL off); MH/OH poison reminder from `GetWeaponEnchantInfo` (presence
    only - charges UNCONFIRMED, no fabricated claim); live `get_hud_state` (SnD/Rupture/EA/AR/BF/
    Tea/Kick; trinkets HUD-served; secret-regime absence -> hidden, never "missing"); live
    `gather_guide_inputs` (energy/CP/tick/TTD/auras/stacks/EA/Shiv/Tea + inputs_unknown ownership
    + M5 lust canary via `api.auras_may_be_secret()`); TTD via `st.druid_energy` D4 EMA with the
    M7 own-provenance rule; POOL/NOW mapping; slot ids resolved from the client's own spell data
    by name (no remembered ids; throttled cold-book retry).
  - `rogue_guide.lua` (CRLF kept): `is_unknown` now honours the explicit `inputs_unknown` bit
    (M6 provider ownership); header contract updated.
  - `tests/rogue_state.lua` 317/0, `tests/rogue_guide_state.lua` 206/0, `tests/guide_contract.lua`
    756/0 (rogue gather->evaluate->frame parity incl. POOL/NOW/unknown/latch cases).
- **Current state:** `bash tests/run.sh` = **37 steps, 0 failed**; luacheck **2 warnings / 0 errors**
  (floor). Mutation battery `/tmp/opencode/muts_rogue_cues.py`: **12/12 bitten** (CP-15, Era gate,
  H4 hide, spark position, M5 bit, engine bit, swap copy, Wrath gate, pool band, poison probe,
  TTD provenance, frame parity), clean-copy sanity PASS. No out-of-scope file touched
  (practice.lua/option_tables.lua changes on disk are the parallel practice lane; TOCs/version/
  CHANGELOG/main/bars/compat untouched).
- **Residuals for the orchestrator:** (1) the new probes (`GetWeaponEnchantInfo`,
  `GetItemCount`/`GetItemCooldown`/`GetItemInfo`, `UnitGUID`) are read via load-time `rawget` in
  `classes/rogue.lua` and are **owed to compat.lua** (out of this lane's scope) - fold them into
  `st.api` in a later pass; (2) poison *charges* intentionally unrendered until the probe shape is
  confirmed in-client; (3) new opt-in keys (`show_rogue_ss_window`, `show_rogue_swap_cue`,
  `show_rogue_poison_cue`, colours, `rogue_ea_duty`, tuning keys) are nil-safe/off and await the
  options pass; (4) in-client checks remain for tick accuracy vs Yam, the Era SS window feel, and
  the Tea count probe shape.
- **Next step:** orchestrator validation (both directions + mutations), then reconcile with the
  practice lane; nothing left open in this lane's files.

