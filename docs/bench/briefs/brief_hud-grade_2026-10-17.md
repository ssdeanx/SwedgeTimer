# Brief: hud-grade — HUD enterprise review
Date: 2026-10-17. Orchestrator-issued. Owner bar: enterprise grade, ready for in-game testing.

## Read first (all verified on disk)
desks/hud/journal.md · desks/journal.md · the five class buildout reports (bench/buildout_{hunter,warrior,paladin,shaman,druid}_2026-10-17.md — what each class HUD is supposed to show) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
hud.lua, rotationtext.lua, tests/rotationtext_state.lua. NOTHING else. tests/hud_state.lua is FORBIDDEN (reconcile wave owns it — report your slot/frame count deltas in your bench report instead). luacheck reports ZERO warnings in this scope — the job is completeness, not wiring.

## Task — every slot live
- Every HUD slot for all 5 classes: shows when it should, hides when it shouldn't, updates from live state (no stale/frozen values). Verify the prior-pass features are actually live: hunter Aimed slot, shaman totem-twist, warrior Rampage, paladin HoW, druid bear chain, plus everything this round added (TF/Berserk, spell-position markers, pips consumers, CD icon groups).
- Hunt for half-wiring: frames created but never shown, slots reading nil keys, show/hide logic contradicting its toggle. Fix in scope; out-of-scope findings go in the report.
- Nil-safety throughout (no client has every aura); no default-visible change.

## Rules
No git, no lint-config, endings preserved. Wire-not-strip for anything found. Never gate on st.is_mainline alone. Other lanes parallel (count fails expected — do NOT touch bars_state/hud_state).

## Validation
bash tests/run.sh (rotationtext green; only known count pins fail). luacheck 0 errors, still 0 warnings in scope. Mutation proofs on /tmp/opencode copy.

## Deliverables
Code · desks/hud/journal.md entry · signal JSON · bench/buildout_hud-grade_2026-10-17.md (slot-by-slot verification table per class; count deltas for the reconcile wave; UNCONFIRMED in-client items). Final reply ≤6 lines. NEVER run git.
