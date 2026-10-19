# Brief: druid — build-out round 1
Date: 2026-10-17. Orchestrator-issued, round plan approved in desks/journal.md.

## Read first (all verified on disk)
desks/druid/journal.md · desks/journal.md · bench/verify_bank.md (D2–D6 rows + §2 TF row + correction §4.1 — BINDING) · bench/discover_features.md (SuperSwingTimer druid section, #4/#8 rows) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
classes/druid.lua, druid_energy.lua, druid_guide.lua, tests/druid_state.lua, tests/druid_energy_state.lua, tests/druid_guide_state.lua. NOTHING else — the pips widget lives in bars-design's scope; you only CALL it.

## Task
- **D2 TF/Berserk HUD slots** (STANDARD): Tiger's Fury via NAME-BASED lookup (correction — ids are rank-dependent: 9845/9846 Era; +5217/6793/50213 WotLK); Berserk(cat) 50334 CONFIRMED WotLK; Era/SoD: not baseline (SoD rune) — gate probes per family.
- **D3 pips wiring**: consume the FROZEN contract in bench/briefs/brief_bars-design_2026-10-17.md — `new_pips(parent, opts)` → frame with `set(count 0–5)` + `glow_full(bool)`. If bench/buildout_bars-design_2026-10-17.md exists when you start, confirm the installed signature; else code to the contract and mark for the reconcile pass.
- **D4 TTD EMA** (correction §4.1 — BINDING): exponential moving average of HP/s (TimeToDie-style smoothing), NOT raw velocity (spikes on crits/DoT ticks); keep integration points/feature tags intact.
- **D5 energy deficit countdown** (STANDARD): "Shred in Xs" style energy-tick math.
- **D6 Maul-efficiency badge** (differentiator §6.3): rage-wasted-at-cap readout.
- **Omen of Clarity proc tracking** (discover #8): proc glow, aura id guarded.
- **Energy tick bar with GCD tick overlay** (discover #4, Wago feral standard): extends druid_energy.
- **D1 remains BLOCKED** (no honest offline probe; reserved plug-in documented) — do not build.

## Cross-client rules
druid_guide_state.lua ~43k checks — never weaken. Form-aware gating via st.api probes. New toggles nil-safe, defaults documented. Minimal in-place edits, no `_` renames, no unused-variable work.

## Validation
bash tests/run.sh — all green. luacheck 0 errors. Mutation proof on /tmp/opencode/mut_druid/ (break the D4 EMA smoothing constant, show the check fails, restore).

## Deliverables
Code · desks/druid/journal.md entry · signal JSON · bench/buildout_druid_2026-10-17.md (changes, evidence, TF name-lookup table, D4 EMA params, option defaults, UNCONFIRMED list). Final reply ≤6 lines. NEVER run git.
