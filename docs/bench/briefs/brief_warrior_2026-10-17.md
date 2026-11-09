# Brief: warrior — build-out round 1
Date: 2026-10-17. Orchestrator-issued, round plan approved in desks/journal.md.

## Read first (all verified on disk)
desks/warrior/journal.md · desks/journal.md · bench/verify_bank.md (W1/W2/W3/W7 rows + correction §4.2 + §5 rows 2/3/9 — BINDING) · bench/discover_features.md (SuperSwingTimer warrior section) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
classes/warrior.lua + tests/warrior_state.lua (EXISTS — extend it; run.sh already runs it). NOT tests/bars_state.lua, NOT tests/hud_state.lua, NOT run.sh, NOT tocs — bars_state count expectations are reconciled in a later wave; report your new frame/texture/fontstring counts in your bench report instead.

## Previous attempt: died mid-flight (rate limit)
warrior.lua + warrior_state.lua carry its partial work — inspect both FIRST, keep what is right, finish the rest. Failures you must clear:
- warrior_state: 2 of 618 (W3 tier: elapsed -> red, got amber; BS badge: toggle off hides a live badge)
- hud_state: 1 of 401 (warrior: an elapsed window stops the glow — CODE bug in your file; do NOT edit hud_state.lua)
- bars_state glow: combat exit stops the glow (8 vs 7 — same glow-lifecycle bug, fix the code)

## Task
- **W1 pre-execute pooling cue** (STANDARD): "BANK" hold + amber edge before 20% / execute phase (SuperSwingTimer EXEC-badge model).
- **W2 BT+WW dual-ready composite + RAGE GATE** (correction §4.2 — BINDING): do not prompt BT when rage < cost + HS reserve; top parsers account for rage before ordering. When HS is queued, the composite must reflect it.
- **W3 Rampage urgency tiers**: badge already shipped in an earlier pass — VERIFY tier behavior vs the standard green/amber/red (SuperSwingTimer Rampage rune support); complete gaps only, no rewrite.
- **W7 OP cue degrade on Mainline-code clients** (correction §4.7 — confirmed): readiness-glow usable-swipe state as the fallback where classic CLEU SWING_* is absent; never gate on st.is_mainline alone — gate on what the swing engine actually reports.
- **HS/Cleave queue tint on MH bar** (§5.2, SuperSwingTimer yellow/green) via class-hook drawing.
- **Shield Block duration bar** (§5.3) above MH stack region via hook drawing.
- **Battle Shout uptime tracking** (discover #9): buff bar/badge with guarded id reads; SoD rune list belongs to a future round, not this one.

## Cross-client rules
New toggles nil-safe, defaults documented. BT/WW/HS/Shield Block/Battle Shout/Overpower ids: guard every read, list UNCONFIRMED/in-client items (BT/WW ids are pending in-client confirmation — code name-based where the API allows).

## Validation
bash tests/run.sh — all green. luacheck 0 errors. Mutation proof on /tmp/opencode/mut_warrior/ (break the W2 rage gate threshold, show the check fails, restore). New suite tests/warrior_state.lua with table-driven checks for the composite ordering + rage gate.

## Deliverables
Code · desks/warrior/journal.md entry · signal JSON · bench/buildout_warrior_2026-10-17.md (changes, evidence, composite truth table, option defaults, UNCONFIRMED list). Final reply ≤6 lines. NEVER run git.
