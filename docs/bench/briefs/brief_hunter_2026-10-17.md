# Brief: hunter — build-out round 1
Date: 2026-10-17. Orchestrator-issued, round plan approved in desks/journal.md.

## Read first (all verified on disk)
desks/hunter/journal.md · desks/journal.md · bench/verify_bank.md (H1/H2/H4/H6 rows + §2 id table + §5 missing rows 1/9/10 — BINDING) · bench/discover_features.md (SuperSwingTimer section) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
classes/hunter.lua, hunter_guide.lua, hunter_ui.lua, hunter_window.lua, tests/hunter_state.lua, tests/hunter_guide_state.lua, tests/hunter_window_state.lua. NOTHING else — draw on bars via the existing generic class hook (`on_bar_update(self, hand)` pattern, as paladin does); do NOT touch bars.lua or hud.lua.

## Previous attempt: died mid-flight (rate limit)
hunter_window.lua + hunter_guide.lua carry its partial edits (classes/hunter.lua untouched) — inspect both FIRST, keep what is right, finish the rest.

## Task
- **H1 Steady-clip numeric shot-clock** (STANDARD): time_to_next_shot numeric + HOLD seconds + safe/unsafe tint; match SuperSwingTimer clip-safety model (0.5s TBC Steady Clip-time grace).
- **H2 lust/haste-window plan** (STANDARD): detect Bloodlust/Heroism window via the FROZEN C2 contract `st.api.scan_player_aura(ids) → duration_remaining, stacks` (implemented in parallel by compat-bl; ids 2825/32182 CONFIRMED; Era NOT APPLICABLE — never arms). If compat-bl hasn't landed when you reach H2, code to the contract and mark for the reconcile pass. Suppress Aimed/Multi in the window, Steady spam cue (standard).
- **H4 pre-cast range gate** (STANDARD): nil=allow, 0=HOLD before cast prompts.
- **H6 BW duration badge + pet Frenzy stacks** (STANDARD, Wago-tracked pattern).
- **Safe-to-move window indicator** (verify_bank §5.1, WeaponSwingTimer standard): movement-safe color/window on the ranged bar.
- **Feign Death ranged reset handling** (§5.9) + **Readiness refresh handling for Rapid Fire** (§5.10) — SuperSwingTimer standards.
- **H3**: DO NOT build multi-target counting. Decision stands: manual toggle fallback (verify_bank correction); list the toggle definition in your bench report for the options pass.
- In-client items (KC 34026, Steady 34120, aspect ids etc.) — guard every read, list as in-client checks with UNCONFIRMED marks.

## Cross-client rules
Never gate on st.is_mainline alone. New toggles nil-safe, defaults documented. Minimal in-place edits, preserve formatting/line endings, no `_` renames, no unused-variable work.

## Validation
bash tests/run.sh — all green. luacheck 0 errors. Mutation proof on /tmp/opencode/mut_hunter/ (break one new rule, e.g. the clip-grace length, show the check fails, restore). Extend the three hunter suites — never weaken.

## Deliverables
Code · desks/hunter/journal.md entry · signal JSON · bench/buildout_hunter_2026-10-17.md (changes, evidence, H3 toggle spec, option defaults, UNCONFIRMED list). Final reply ≤6 lines. NEVER run git.
