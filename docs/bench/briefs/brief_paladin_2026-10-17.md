# Brief: paladin — build-out round 1
Date: 2026-10-17. Orchestrator-issued, round plan approved in desks/journal.md.

## Read first (all verified on disk)
desks/paladin/journal.md · desks/journal.md · bench/verify_bank.md (P1/P2/P3/P6/P7 rows + §2 21183 row — BINDING) · bench/discover_features.md (SuperSwingTimer paladin section) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
classes/paladin.lua, nextaction.lua, nextaction_ui.lua, tests/nextaction_state.lua, tests/twist_state.lua, + NEW tests/paladin_state.lua (does not exist yet). NOT tests/bars_state.lua (frame-count expectations reconciled in a later wave — report your new frame/texture/fontstring counts instead). No bars.lua/hud.lua; icons belong to your own UI files.

## Previous attempt: died mid-flight (rate limit)
paladin.lua + nextaction.lua carry its partial work — inspect both FIRST, keep what is right, finish the rest. Failures you must clear:
- wiring_check: `ST.PALADIN.aow_exo_pulse_start(` defined but NEVER called — wire it into the P6 flow (or remove the stub if the feature took another shape; either way wiring_check must go green).

## Task
- **P1 live twist hit-rate badge** (differentiator, verify §6.1): session attempts/successes from the existing twist state; nothing like it ships in WeakAuras — keep it simple and truthful (reset per session; per-profile counts optional, default OFF).
- **P2 JotC uptime mini-bar** (STANDARD): id 21183 CONFIRMED (20s max rank, refreshed by melee strikes → uptime window extends on melee hits; lower ranks 10s). FS-bar-clone styling per bank.
- **P3 lust rotation override** (STANDARD): twist window narrows under Bloodlust/Heroism via the FROZEN C2 contract `st.api.scan_player_aura(ids)` (ids 2825/32182, Era NOT APPLICABLE — never arms). If compat-bl hasn't landed yet, code to the contract and mark for reconcile.
- **P6 AoW+Exo overlap pulse** (STANDARD): transition-guarded pixel-glow pulse; no churn.
- **P7 seal-icon texture churn perf**: move seal icon resolution to aura/state-change events only (no per-frame SetTexture where state didn't change).
- **CD icon group** (discover #5, approved in round plan): AW, Divine Shield, HoJ, BoP, Holy Wrath, LoH + racials; adaptive icon row, gold glow last 4s; HU-3 resolved: distinct from P2 (cooldowns vs debuff uptime) — both ship.
- Era seals/HoW + Forever seal/VR/Farseer/SP ids: guard every read; in-client list stays.

## Cross-client rules
Keep tests/twist_state.lua pins intact (extend, never weaken). Guides stay OFF by default except paladin. New toggles nil-safe, defaults documented. Minimal in-place edits, no `_` renames, no unused-variable work.

## Validation
bash tests/run.sh — all green. luacheck 0 errors. Mutation proof on /tmp/opencode/mut_paladin/ (break the P2 refresh-on-melee semantics, show the check fails, restore).

## Deliverables
Code · desks/paladin/journal.md entry · signal JSON · bench/buildout_paladin_2026-10-17.md (changes, evidence, icon-group id table, option defaults, UNCONFIRMED list). Final reply ≤6 lines. NEVER run git.
