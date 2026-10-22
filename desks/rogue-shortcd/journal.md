# rogue-shortcd — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build competitor gap R3 (short-CD row: Kick/Kidney/Re-stealth/Bandage + multi-CD yellow glow) per bench/competitor_gaps_2026-10-19.md §Rogue R3 + bench/rogue_deep_2026-10-19.md §§2.4/2.7.
- **Scope:** ONLY classes/rogue.lua, rogue_guide.lua, tests/rogue_state.lua, tests/rogue_guide_state.lua, tests/guide_contract.lua (rogue parts). R2 poison charges OUT. Everything else OUT.
- **Next step:** Read bench sources (done via orchestrator context), verify APIs vs /home/sam/wow-ui-source, implement nil-safe + unknown-hides + no default-visible change, harness + luacheck + mutations on /tmp/opencode copies.

## 2026-10-19 — R3 built, target suites green
- **Worked on:** Short-CD slots (kidney/restealth/bandage appended to HUD_SLOTS, provider-gated `== true`), Vanish-buff-wins restealth, Tea-shaped bandage item probes, AR+BF stacked glow via pure `rogue_guide.stacked_glow`; pure helper + pins in rogue_guide_state (223 checks), rogue_state (352 checks, new §12), guide_contract rogue R3 pins (763 checks).
- **Current state:** rogue_state 352/0, rogue_guide_state 223/0, guide_contract 763 PASS, 5-file luacheck 0/0, full-tree luacheck 2/0 (floor kept), CRLF/LF endings preserved, 5 mutations kill (gate/glow/pure/bandage/name). Full harness has 3 failures OUT of scope and pre-existing (hunter_state 2, bars_state 2, wiring_check 2+3 accepted) — untouched files, no rogue load path.
- **Next step:** Orchestrator validation + in-client confirmation of UNCONFIRMED tunables (Vanish mapping, bandage rank, stacked set beyond AR+BF, Tea-style thresholds).

## 2026-10-19 — [signal:done] R3 short-CD row + stacked glow ready for review
- Target suites green + 5/5 mutations kill on /tmp/opencode copies; no default-visible change (nil hides); R2 untouched.
